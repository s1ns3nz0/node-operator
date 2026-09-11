"""Read-only target discovery. Success is not proof of provisioning permission."""
from __future__ import annotations

import json
import hashlib
import os
import re
import shutil
import subprocess


class PreflightError(RuntimeError):
    """A non-sensitive actionable preflight failure."""


def local_prerequisites() -> dict:
    """Report missing stage tools together, without installing or executing them.

    Presence is not a version or runtime-health check. Keep optional custody
    tools separate so a node-only installation need not generate a validator.
    """
    stages = {
        "infrastructure": ("aws", "terraform", "jq", "shasum", "rg"),
        "ops_access": ("aws", "session-manager-plugin", "kubectl", "nc", "mktemp", "unlink"),
        "vault": ("vault", "openssl", "kubectl"),
        "custody": ("curl", "shasum", "tar", "mkdir", "chmod", "find", "gh"),
    }
    available = {tool: shutil.which(tool) is not None
                 for tool in sorted({tool for tools in stages.values() for tool in tools})}
    return {
        "missing_by_stage": {stage: [tool for tool in tools if not available[tool]]
                             for stage, tools in stages.items()},
        "versions": "not_verified",
        "runtime_health": "not_verified",
    }


def validate_inputs(profile: str, region: str, name: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", profile):
        raise PreflightError("Use an AWS profile name containing letters, digits, dots, underscores or hyphens.")
    if region not in {"ap-northeast-1", "ap-northeast-2"}:
        raise PreflightError("Choose ap-northeast-1 or ap-northeast-2.")
    if not re.fullmatch(r"[a-z][a-z0-9-]{1,18}[a-z0-9]", name):
        raise PreflightError("Deployment name must be 3-20 lowercase DNS characters.")


def backend_collisions(profile: str, region: str, name: str, account: str) -> dict:
    """Check deterministic backend names; never treat foreign S3 names as free.

    AWS CLI pagination must stay enabled. This checks account-owned buckets,
    not global S3 availability, and cannot authorize adoption on resume.
    """
    bucket = f"{name}-tfstate-{account}-{region.replace('-', '')}"
    logs = f"{bucket[:48]}-{hashlib.sha256(bucket.encode()).hexdigest()[:8]}-logs"
    table = f"{name}-terraform-lock"
    buckets = aws_read(profile, region, ["s3api", "list-buckets", "--query", "Buckets[].Name"])
    tables = aws_read(profile, region, ["dynamodb", "list-tables", "--query", "TableNames"])
    for values in (buckets, tables):
        if not isinstance(values, list) or not all(isinstance(value, str) for value in values):
            raise PreflightError("AWS backend inventory is incomplete; no resource name is considered available.")
    return {
        "account_owned_bucket_conflicts": sorted({bucket, logs}.intersection(buckets)),
        "regional_table_conflicts": [table] if table in tables else [],
        "global_bucket_availability": "not_verified",
        "existing_resource_adoption": "not_authorized",
    }


def iam_role_collisions(profile: str, region: str, name: str) -> dict:
    """Inventory only role names Terraform can derive for this deployment.

    IAM has no role-name-prefix filter, so the AWS CLI's default paginator reads
    list-roles pages and this function retains only the two deployment
    namespaces.  This neither inventories policy attachments nor verifies that
    the caller has every IAM permission required for an apply.
    """
    foundation_flow_logs = f"{name}-foundation-flow-logs"
    baseline_prefix = f"{name}-baseline-"
    roles = aws_read(profile, region, ["iam", "list-roles", "--query", "Roles[].RoleName"])
    if (not isinstance(roles, list)
            or not all(isinstance(role, str)
                       and re.fullmatch(r"[A-Za-z0-9+=,.@_-]{1,64}", role)
                       for role in roles)):
        raise PreflightError("AWS IAM role inventory is incomplete; no role name is considered available.")
    return {
        "deployment_role_name_conflicts": sorted({role for role in roles
                                                   if role == foundation_flow_logs
                                                   or role.startswith(baseline_prefix)}),
        "checked_role_namespaces": {
            "foundation_flow_logs": foundation_flow_logs,
            "baseline_prefix": baseline_prefix,
        },
        "role_policies": "not_verified",
        "iam_permissions": "not_verified",
    }


def aws_read(profile: str, region: str, arguments: list[str]) -> object:
    if shutil.which("aws") is None:
        raise PreflightError("AWS CLI is missing; install it before target discovery.")
    environment = os.environ.copy()
    # Explicit profile must not silently inherit a different credential pair.
    # GitHub credentials and the caller's environment are never modified.
    for key in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "AWS_SECURITY_TOKEN"):
        environment.pop(key, None)
    environment["AWS_PAGER"] = ""
    environment["AWS_CLI_AUTO_PROMPT"] = "off"
    try:
        result = subprocess.run(
            ["aws", "--profile", profile, "--region", region, "--no-cli-pager", *arguments, "--output", "json"],
            env=environment, stdin=subprocess.DEVNULL, capture_output=True, text=True,
            timeout=45, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise PreflightError("AWS discovery timed out or could not start; check CLI connectivity and retry.") from exc
    if result.returncode:
        raise PreflightError("AWS read-only discovery failed; check the selected profile login and the requested service read permissions. No resources were created.")
    try:
        return json.loads(result.stdout)
    except (ValueError, TypeError) as exc:
        raise PreflightError("AWS returned an invalid discovery response.") from exc


def discover(profile: str, region: str, name: str) -> dict:
    validate_inputs(profile, region, name)
    identity = aws_read(profile, region, ["sts", "get-caller-identity"])
    if not isinstance(identity, dict) or not re.fullmatch(r"[0-9]{12}", str(identity.get("Account", ""))):
        raise PreflightError("AWS identity did not provide a valid account ID.")
    account = identity["Account"]
    arn = identity.get("Arn", "")
    if not isinstance(arn, str) or not arn.startswith((f"arn:aws:iam::{account}:", f"arn:aws:sts::{account}:")):
        raise PreflightError("AWS identity account and principal do not match.")
    if arn.endswith(":root"):
        raise PreflightError("Do not deploy using the AWS root identity; select a scoped operator profile.")
    zones = aws_read(profile, region, ["ec2", "describe-availability-zones", "--filters", "Name=state,Values=available"])
    if not isinstance(zones, dict) or not isinstance(zones.get("AvailabilityZones"), list):
        raise PreflightError("AWS availability-zone response is incomplete.")
    available = sorted({z["ZoneName"] for z in zones["AvailabilityZones"]
                        if isinstance(z, dict) and z.get("State") == "available"
                        and re.fullmatch(re.escape(region) + r"[a-z]", str(z.get("ZoneName", "")))})
    if len(available) < 2:
        raise PreflightError("At least two available standard availability zones are required.")
    clusters = aws_read(profile, region, ["eks", "list-clusters"])
    if not isinstance(clusters, dict) or not isinstance(clusters.get("clusters"), list) or not all(isinstance(c, str) for c in clusters["clusters"]):
        raise PreflightError("AWS cluster inventory is incomplete.")
    return {"aws_account_id": account, "aws_profile": profile, "aws_region": region,
            "deployment_name": name, "availability_zones": available[:2],
            "cluster_name_present": name in clusters["clusters"],
            "local_prerequisites": local_prerequisites(),
            "backend_collisions": backend_collisions(profile, region, name, account),
            "iam_role_collisions": iam_role_collisions(profile, region, name),
            "provisioning_permissions": "not_verified", "quotas": "not_verified",
            "other_resource_collisions": "not_verified"}
