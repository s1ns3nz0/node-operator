"""Read-only target discovery. Success is not proof of provisioning permission."""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess


class PreflightError(RuntimeError):
    """A non-sensitive actionable preflight failure."""


def validate_inputs(profile: str, region: str, name: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", profile):
        raise PreflightError("Use an AWS profile name containing letters, digits, dots, underscores or hyphens.")
    if region not in {"ap-northeast-1", "ap-northeast-2"}:
        raise PreflightError("Choose ap-northeast-1 or ap-northeast-2.")
    if not re.fullmatch(r"[a-z][a-z0-9-]{1,18}[a-z0-9]", name):
        raise PreflightError("Deployment name must be 3-20 lowercase DNS characters.")


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
        raise PreflightError("AWS read-only discovery failed; check the selected profile login and STS/EC2/EKS read permissions. No resources were created.")
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
            "provisioning_permissions": "not_verified", "quotas": "not_verified",
            "other_resource_collisions": "not_verified"}
