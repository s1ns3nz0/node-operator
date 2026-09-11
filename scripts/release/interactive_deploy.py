"""Interactive deployment entrypoint: discovery and guarded infrastructure/SSM steps.

Infrastructure and separate SSM apply require terminal confirmation; later adapters remain unimplemented.
"""
from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path
import stat
import sys

from installer_preflight import PreflightError, discover, validate_inputs, verify_backend_role, verify_execution_profile, bootstrap_permission_probe
from installer_state import CheckpointStore, StateError, STAGE_NAMES
from installer_infrastructure import InfrastructureError, prepare_inputs, apply_infrastructure


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
    parser = argparse.ArgumentParser(description="Start/status/resume discovery and separately confirmed infrastructure/SSM execution.")
    parser.add_argument("command", choices=("start", "status", "resume"))
    parser.add_argument("--state-dir", required=True, type=Path)
    parser.add_argument("--release-dir", type=Path, help="Downloaded release asset directory; required for start/resume")
    parser.add_argument("--aws-profile")
    parser.add_argument("--aws-region")
    parser.add_argument("--name")
    parser.add_argument("--prepare-infrastructure", action="store_true", help="Materialize verified release and generate local Terraform inputs; does not apply")
    parser.add_argument("--prepare-ops-access", action="store_true", help="Prepare separate SSM inputs after infrastructure completion; never plans, applies or opens a session")
    parser.add_argument("--plan-ops-access", action="store_true", help="Create a separate private SSM saved plan; does not apply")
    parser.add_argument("--apply-ops-access", action="store_true", help="Apply the separately reviewed SSM plan after terminal confirmation")
    parser.add_argument("--ops-plan-sha", help="Exact SHA-256 from the reviewed SSM plan; required for SSM apply")
    parser.add_argument("--apply-infrastructure", action="store_true", help="Prepare and apply infrastructure after terminal confirmation; does not set up SSM/Vault/workloads")
    parser.add_argument("--backend-principal-arn", help="Exact same-account backend IAM role for infrastructure preparation")
    parser.add_argument("--execution-profile", help="Optional existing AWS role profile to verify and use for infrastructure execution")
    args = parser.parse_args(argv)
    ops_requested = args.prepare_ops_access or args.plan_ops_access or args.apply_ops_access
    if ops_requested and (args.command != "resume" or args.prepare_infrastructure or args.apply_infrastructure or args.backend_principal_arn or args.execution_profile or sum((args.prepare_ops_access, args.plan_ops_access, args.apply_ops_access)) != 1):
        raise StateError("SSM is a separate resume operation; choose one preparation, plan or apply step without infrastructure options.")
    if args.ops_plan_sha and not args.apply_ops_access:
        raise StateError("--ops-plan-sha is accepted only with --apply-ops-access.")
    if args.apply_ops_access and (not sys.stdin.isatty() or not re.fullmatch(r"[0-9a-f]{64}", args.ops_plan_sha or "")):
        raise StateError("SSM apply requires an interactive terminal and the reviewed 64-character plan SHA-256.")
    if args.apply_infrastructure:
        if not sys.stdin.isatty():
            raise StateError("Infrastructure apply requires an interactive terminal and deployment-scope confirmation.")
        args.prepare_infrastructure = True
    if not args.state_dir.is_absolute():
        raise StateError("Use an absolute state directory.")
    if args.command == "status":
        if args.release_dir or args.aws_profile or args.aws_region or args.name or args.prepare_infrastructure or args.backend_principal_arn or args.execution_profile:
            raise StateError("status accepts only --state-dir; it does not query AWS.")
        context = load_context(args.state_dir)
        store = CheckpointStore(args.state_dir, context)
        with store.lock():
            checkpoint = store.resume()
        print(json.dumps({"context": context, "stages": checkpoint["stages"], "deployment_complete": False}, sort_keys=True))
        return 0
    if args.backend_principal_arn and not args.prepare_infrastructure:
        raise StateError("--backend-principal-arn requires --prepare-infrastructure.")
    if args.execution_profile and not args.prepare_infrastructure:
        raise StateError("--execution-profile requires --prepare-infrastructure.")
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
    ops_result = None
    ops_plan_sha = None
    with store.lock():
        checkpoint = store.resume()
        if any(stage["status"] == "running" for stage in checkpoint["stages"].values()):
            raise StateError("An interrupted stage requires reconciliation. No stage was retried or marked complete.")
        if not ops_requested:
            for stage in sorted(STAGE_NAMES):
                if stage not in checkpoint["stages"]:
                    store.set_stage(stage, "pending")
        # Read-only discovery is useful but does not prove permissions, quotas,
        # all-resource collision safety or provisioning readiness.
        if not ops_requested:
            store.set_stage("preflight", "awaiting_input")
        if ops_requested:
            if checkpoint["stages"].get("infrastructure", {}).get("status") != "complete":
                raise StateError("SSM operations require completed infrastructure in this original state directory.")
            if checkpoint["stages"].get("ops_access", {}).get("status") == "complete":
                raise StateError("SSM access is already complete; preparation cannot reset its status.")
            from installer_bundle import materialize_release
            from installer_ops_access import prepare_ops_access
            bundle_root = materialize_release(args.release_dir, args.state_dir / "release",
                                              release["release_sha"], release["bundle_digest"])
            if args.prepare_ops_access:
                prepare_ops_access(bundle_root, args.state_dir, discovery, profile)
                store.set_stage("ops_access", "awaiting_input")
                ops_result = "ops_access_inputs_ready"
            else:
                from installer_ops_execution import plan_ops_access, apply_ops_access
                if args.apply_ops_access:
                    confirmation = f"APPLY SSM {discovery['aws_account_id']} {region} {name} node-operator/ops-access/terraform.tfstate {args.ops_plan_sha}"
                    print("This applies only the separately reviewed SSM access plan. A successful apply does not prove session or private EKS readiness.", file=sys.stderr)
                    if prompt(None, "Type exactly " + confirmation) != confirmation:
                        raise StateError("SSM apply cancelled; no resource changes requested.")
                store.set_stage("ops_access", "running")
                try:
                    if args.plan_ops_access:
                        ops_plan_sha = plan_ops_access(bundle_root, args.state_dir, discovery, profile)
                        ops_result = "ops_access_plan_ready"
                    else:
                        apply_ops_access(bundle_root, args.state_dir, discovery, profile, args.ops_plan_sha)
                        ops_result = "ops_access_provisioned"
                except (InfrastructureError, PreflightError):
                    store.set_stage("ops_access", "failed")
                    raise
                # Provisioning alone does not prove SSM Online or private EKS access.
                store.set_stage("ops_access", "awaiting_input")
        if args.prepare_infrastructure:
            from installer_bundle import materialize_release
            principal = prompt(args.backend_principal_arn, "Same-account Terraform backend IAM role ARN")
            # Validate the role/context before writing the release tree.
            from installer_infrastructure import expected_inputs
            inputs_dir = args.state_dir / "infrastructure-inputs"
            expected_inputs(inputs_dir, discovery, principal)
            discovery["backend_role"] = verify_backend_role(discovery, principal)
            if args.execution_profile:
                discovery["execution_identity"] = verify_execution_profile(discovery, discovery["backend_role"], args.execution_profile)
                discovery["bootstrap_permission_probe"] = bootstrap_permission_probe(discovery, discovery["backend_role"])
            bundle_root = materialize_release(args.release_dir, args.state_dir / "release",
                                              release["release_sha"], release["bundle_digest"])
            prepare_inputs(bundle_root, inputs_dir, discovery, principal)
            store.set_stage("infrastructure", "awaiting_input")
            if args.apply_infrastructure:
                if args.execution_profile and discovery["bootstrap_permission_probe"]["result"] != "limited_checks_passed":
                    raise StateError("Execution role prerequisites need permission review; no infrastructure apply was started.")
                replica_region = "ap-northeast-2" if region == "ap-northeast-1" else "ap-northeast-1"
                confirmation = f"APPLY {discovery['aws_account_id']} {region} {name} AUDIT {replica_region}"
                print("This provisions infrastructure and audit-replica resources in the displayed Regions. Full permission/quota clearance is not proven. Existing state is preserved on failure.", file=sys.stderr)
                if prompt(None, "Type exactly " + confirmation) != confirmation:
                    raise StateError("Infrastructure apply cancelled; no resource changes requested.")
                store.set_stage("infrastructure", "running")
                try:
                    apply_infrastructure(bundle_root, args.state_dir, discovery, principal, args.execution_profile or profile)
                except (InfrastructureError, PreflightError):
                    store.set_stage("infrastructure", "failed")
                    raise
                store.set_stage("infrastructure", "complete")
    print(json.dumps({"result": ops_result or ("infrastructure_ready" if args.apply_infrastructure else ("infrastructure_inputs_ready" if args.prepare_infrastructure else "discovery_complete")), "discovery": discovery,
                      "ops_plan_sha256": ops_plan_sha,
                      "deployment_complete": False,
                      "remaining": "SSM session/private EKS readiness, Vault, secrets, GitOps, workloads, custody, deposit, activation, duty and E2E remain required." if ops_requested or args.apply_infrastructure else "Infrastructure apply and later deployment stages remain required."}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(run())
    except (StateError, PreflightError, InfrastructureError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
    except (OSError, ValueError, KeyError, KeyboardInterrupt):
        print("Installer input/state failed or execution was interrupted. Preserve this state directory; resources may exist and must be reconciled before retrying.", file=sys.stderr)
        raise SystemExit(1)
