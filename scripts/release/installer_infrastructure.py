"""Prepare context-bound infrastructure inputs using the verified release.

No Terraform, cluster, registry, or Vault operations occur in this module.
Prepared files are not evidence of permissions or successful provisioning.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile

from installer_preflight import validate_inputs
from installer_files import publish_directory


class InfrastructureError(RuntimeError):
    """Controlled non-sensitive preparation failure."""


def expected_inputs(destination: Path, discovery: dict, principal: str) -> dict:
    account = discovery["aws_account_id"]
    region = discovery["aws_region"]
    name = discovery["deployment_name"]
    validate_inputs(discovery["aws_profile"], region, name)
    if not re.fullmatch(r"[0-9]{12}", account):
        raise InfrastructureError("Infrastructure account is invalid.")
    if not re.fullmatch(r"arn:aws:iam::" + account + r":role/[A-Za-z0-9+=,.@_/-]+", principal):
        raise InfrastructureError("Provide an exact same-account backend IAM role ARN.")
    zones = discovery["availability_zones"]
    if (not isinstance(zones, list) or len(zones) != 2 or zones[0] == zones[1]
            or not all(isinstance(zone, str) and re.fullmatch(re.escape(region) + r"[a-z]", zone) for zone in zones)):
        raise InfrastructureError("Infrastructure preparation requires two verified target-region AZs.")
    return {
        "bootstrap-state.tfvars.json": {"aws_account_id": account, "aws_region": region, "name": name,
                                       "state_bucket_name": None, "backend_principal_arns": [principal]},
        "foundation-network.tfvars.json": {"aws_region": region, "name": name, "network_mode": "fresh", "availability_zones": zones},
        "baseline.tfvars.json": {
            "aws_account_id": account, "aws_region": region, "name": name,
            "terraform_apply_role_arn": principal,
            "audit_replica_region": "ap-northeast-2" if region == "ap-northeast-1" else "ap-northeast-1",
            "availability_zones": zones, "enable_gitops_client_ecr_publisher": True,
            "enable_temporary_ssm_ops_host": False, "temporary_ssm_ops_host_termination_at": "",
            "enable_argocd_bootstrap_runner": False, "enable_argocd_bootstrap_cluster_admin": False,
            "enable_vault_bootstrap_runner": False, "enable_vault_bootstrap_cluster_admin": False,
        },
        "zero-resource-inputs.json": {"schema_version": 1, "aws_account_id": account, "aws_region": region,
                                     "availability_zones": zones, "name": name,
                                     "bootstrap_config": str(destination / "bootstrap-state.tfvars.json"),
                                     "foundation_config": str(destination / "foundation-network.tfvars.json"),
                                     "baseline_config": str(destination / "baseline.tfvars.json")},
    }


def _read_object(path: Path) -> dict:
    def unique(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise InfrastructureError("Infrastructure input has duplicate fields.")
            value[key] = item
        return value
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(descriptor, "r", encoding="utf-8") as handle:
            info = os.fstat(handle.fileno())
            if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or info.st_size > 65536:
                raise InfrastructureError("Infrastructure input is not a bounded private regular file.")
            result = json.load(handle, object_pairs_hook=unique)
    except (OSError, ValueError) as error:
        raise InfrastructureError("Infrastructure input could not be read safely.") from error
    if not isinstance(result, dict):
        raise InfrastructureError("Infrastructure input is not a JSON object.")
    return result


def _validate_tree(directory: Path, expected: dict) -> None:
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o700:
        raise InfrastructureError("Infrastructure input directory must be private and not a symlink.")
    if {path.name for path in directory.iterdir()} != set(expected):
        raise InfrastructureError("Infrastructure input directory contains missing or unexpected files.")
    for name, value in expected.items():
        # Canonical JSON comparison also distinguishes booleans from numbers.
        if json.dumps(_read_object(directory / name), sort_keys=True) != json.dumps(value, sort_keys=True):
            raise InfrastructureError("Infrastructure inputs differ from the selected deployment context; nothing was overwritten.")


def prepare_inputs(bundle_root: Path, destination: Path, discovery: dict, principal: str) -> Path:
    expected = expected_inputs(destination, discovery, principal)
    if not destination.is_absolute() or Path(os.path.normpath(str(destination))) != destination:
        raise InfrastructureError("Infrastructure input directory must be a normalized absolute path.")
    for path in (destination.parent, *destination.parent.parents):
        if path.is_symlink() or not path.is_dir():
            raise InfrastructureError("Infrastructure input ancestors must be existing regular directories.")
    if destination.exists() or destination.is_symlink():
        _validate_tree(destination, expected)
        return destination / "zero-resource-inputs.json"
    script = bundle_root / "source/scripts/release/prepare-zero-resource-inputs.sh"
    if not script.is_file() or script.is_symlink():
        raise InfrastructureError("Verified release lacks its infrastructure input preparation command.")
    environment = os.environ.copy()
    for key in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "AWS_SECURITY_TOKEN", "BASH_ENV", "ENV"):
        environment.pop(key, None)
    environment.update(AWS_PROFILE=discovery["aws_profile"], AWS_REGION=discovery["aws_region"], AWS_DEFAULT_REGION=discovery["aws_region"])
    stage = Path(tempfile.mkdtemp(prefix=".infrastructure-inputs-", dir=destination.parent))
    generated = stage / "generated"
    try:
        args = ["bash", str(script), "--aws-account-id", discovery["aws_account_id"],
                "--aws-region", discovery["aws_region"], "--name", discovery["deployment_name"],
                "--backend-principal-arn", principal, "--output-dir", str(generated)]
        for zone in discovery["availability_zones"]:
            args.extend(["--availability-zone", zone])
        result = subprocess.run(args, env=environment, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30, check=False)
        if result.returncode:
            raise InfrastructureError("Release input preparation failed; no infrastructure was applied.")
        _validate_tree(generated, expected_inputs(generated, discovery, principal))
        # The release command emitted absolute staging paths; bind those paths
        # to the final private directory before publishing it atomically.
        (generated / "zero-resource-inputs.json").write_text(json.dumps(expected["zero-resource-inputs.json"], sort_keys=True) + "\n")
        _validate_tree(generated, expected)
        if destination.exists() or destination.is_symlink():
            raise InfrastructureError("Infrastructure input destination appeared during preparation.")
        publish_directory(generated, destination)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise InfrastructureError("Infrastructure preparation could not complete; no resources were applied.") from error
    finally:
        shutil.rmtree(stage)
    return destination / "zero-resource-inputs.json"
