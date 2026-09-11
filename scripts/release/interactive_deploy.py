"""Interactive deployment entrypoint: release discovery and local input preparation.

Provisioning adapters are not yet connected. Never report discovery as deployment.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import stat
import sys

from installer_preflight import PreflightError, discover, validate_inputs
from installer_state import CheckpointStore, StateError, STAGE_NAMES
from installer_infrastructure import InfrastructureError, prepare_inputs


def load_context(directory: Path) -> dict:
    # No symlink traversal at the state-directory or checkpoint boundary.
    value = directory.lstat()
    if not stat.S_ISDIR(value.st_mode) or stat.S_IMODE(value.st_mode) != 0o700:
        raise StateError("State directory must be a private regular directory.")
    fd = os.open(directory / "checkpoint.json", os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "r", encoding="utf-8") as handle:
        info = os.fstat(handle.fileno())
        if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or info.st_size > 65536:
            raise StateError("Checkpoint is not a bounded private regular file.")
        data = json.load(handle)
    if not isinstance(data, dict) or not isinstance(data.get("context"), dict):
        raise StateError("Checkpoint context is invalid.")
    # Full strict JSON/state validation is performed again under the store lock.
    return data["context"]


def prompt(value: str | None, label: str, default: str | None = None) -> str:
    if value is not None:
        return value
    if not sys.stdin.isatty():
        raise StateError("Missing input requires a terminal or an explicit command option.")
    answer = input(label + (f" [{default}]" if default else "") + ": ").strip()
    return answer or default or ""


def run(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Start/status/resume release discovery and optional local infrastructure preparation. No provisioning is performed in this version.")
    parser.add_argument("command", choices=("start", "status", "resume"))
    parser.add_argument("--state-dir", required=True, type=Path)
    parser.add_argument("--release-dir", type=Path, help="Downloaded release asset directory; required for start/resume")
    parser.add_argument("--aws-profile")
    parser.add_argument("--aws-region")
    parser.add_argument("--name")
    parser.add_argument("--prepare-infrastructure", action="store_true", help="Materialize verified release and generate local Terraform inputs; does not apply")
    parser.add_argument("--backend-principal-arn", help="Exact same-account backend IAM role for infrastructure preparation")
    args = parser.parse_args(argv)
    if not args.state_dir.is_absolute():
        raise StateError("Use an absolute state directory.")
    if args.command == "status":
        if args.release_dir or args.aws_profile or args.aws_region or args.name or args.prepare_infrastructure or args.backend_principal_arn:
            raise StateError("status accepts only --state-dir; it does not query AWS.")
        context = load_context(args.state_dir)
        store = CheckpointStore(args.state_dir, context)
        with store.lock():
            checkpoint = store.resume()
        print(json.dumps({"context": context, "stages": checkpoint["stages"], "deployment_complete": False}, sort_keys=True))
        return 0
    if args.backend_principal_arn and not args.prepare_infrastructure:
        raise StateError("--backend-principal-arn requires --prepare-infrastructure.")
    if args.release_dir is None:
        raise StateError("start/resume requires --release-dir with verified release assets.")
    from installer_bundle import verify_release
    release = verify_release(args.release_dir)
    if args.command == "resume":
        original = load_context(args.state_dir)
        profile = args.aws_profile or original["aws_profile"]
        region = args.aws_region or original["aws_region"]
        name = args.name or original["deployment_name"]
    else:
        if args.state_dir.exists() or args.state_dir.is_symlink():
            raise StateError("State path already exists. Use resume; no state was overwritten.")
        profile = prompt(args.aws_profile, "AWS profile", "default")
        region = prompt(args.aws_region, "AWS Region", "ap-northeast-1")
        name = prompt(args.name, "Deployment name")
    validate_inputs(profile, region, name)
    discovery = discover(profile, region, name)
    context = {key: discovery[key] for key in ("aws_profile", "aws_region", "aws_account_id", "deployment_name")}
    context.update(release_sha=release["release_sha"], bundle_digest=release["bundle_digest"])
    store = CheckpointStore(args.state_dir, context)
    with store.lock():
        checkpoint = store.resume()
        if any(stage["status"] == "running" for stage in checkpoint["stages"].values()):
            raise StateError("An interrupted stage requires reconciliation. No stage was retried or marked complete.")
        for stage in sorted(STAGE_NAMES):
            if stage not in checkpoint["stages"]:
                store.set_stage(stage, "pending")
        # Read-only discovery is useful but does not prove permissions, quotas,
        # all-resource collision safety or provisioning readiness.
        store.set_stage("preflight", "awaiting_input")
        if args.prepare_infrastructure:
            from installer_bundle import materialize_release
            principal = prompt(args.backend_principal_arn, "Same-account Terraform backend IAM role ARN")
            # Validate the role/context before writing the release tree.
            from installer_infrastructure import expected_inputs
            inputs_dir = args.state_dir / "infrastructure-inputs"
            expected_inputs(inputs_dir, discovery, principal)
            bundle_root = materialize_release(args.release_dir, args.state_dir / "release",
                                              release["release_sha"], release["bundle_digest"])
            prepare_inputs(bundle_root, inputs_dir, discovery, principal)
            store.set_stage("infrastructure", "awaiting_input")
    print(json.dumps({"result": "infrastructure_inputs_ready" if args.prepare_infrastructure else "discovery_complete", "discovery": discovery,
                      "deployment_complete": False,
                      "remaining": "Still required: full permission/quota/collision preflight and infrastructure apply integration."}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(run())
    except (StateError, PreflightError, InfrastructureError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
    except (OSError, ValueError, KeyError, KeyboardInterrupt):
        print("Installer input or local state could not be read safely. No automatic cleanup or deployment was performed.", file=sys.stderr)
        raise SystemExit(1)
