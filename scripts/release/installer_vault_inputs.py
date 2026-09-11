"""Bind reviewed non-secret Vault artifacts to completed baseline outputs."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile

from installer_files import publish_directory
from installer_infrastructure import InfrastructureError, _read_object, _validate_tree, expected_inputs
from installer_ops_execution import _private, _safe_state

class VaultInputsError(InfrastructureError): pass

_IMAGE = re.compile(r"[0-9]{12}\.dkr\.ecr\.ap-northeast-(?:1|2)\.amazonaws\.com/[a-z0-9][a-z0-9._/-]*@sha256:[a-f0-9]{64}\Z")
_KMS = re.compile(r"arn:aws:kms:ap-northeast-(?:1|2):[0-9]{12}:key/[A-Za-z0-9-]+\Z")
_INDEX_COMPONENTS = {
    "vault-bootstrap", "vault-audit-relay", "gitops-oci-mirror", "vault-server", "vault-injector",
    "cert-manager-controller", "cert-manager-webhook", "cert-manager-cainjector",
    "cert-manager-startupapicheck", "vault-chart", "cert-manager-chart",
}
_MIRRORED_ARTIFACTS = _INDEX_COMPONENTS - {"gitops-oci-mirror"}

def _read(path: Path, message: str) -> dict:
    try: return _read_object(path)
    except InfrastructureError as error: raise VaultInputsError(message) from error

def _value(output: dict, name: str):
    value = output.get(name)
    if not isinstance(value, dict) or set(value) - {"sensitive", "type", "value"} or "value" not in value or value.get("sensitive") is not False:
        raise VaultInputsError("Baseline output is missing a bounded Vault input.")
    return value["value"]

def _artifact(path: Path, discovery: dict) -> tuple[dict, str]:
    value = _read(path, "Reviewed Vault artifact manifest could not be read safely.")
    if set(value) != {"schema_version", "aws_account_id", "aws_region", "deployment_name", "images", "chart"}:
        raise VaultInputsError("Reviewed Vault artifact manifest has unexpected fields.")
    if not (type(value["schema_version"]) is int and value["schema_version"] == 1
            and all(value[key] == discovery[field] for key, field in (("aws_account_id", "aws_account_id"), ("aws_region", "aws_region"), ("deployment_name", "deployment_name")))):
        raise VaultInputsError("Reviewed Vault artifact manifest does not bind the selected deployment.")
    images = value["images"]
    if not isinstance(images, dict) or set(images) != {"bootstrap", "server", "agent", "injector", "audit_relay"}:
        raise VaultInputsError("Reviewed Vault artifact manifest has an invalid image set.")
    prefix = f'{discovery["aws_account_id"]}.dkr.ecr.{discovery["aws_region"]}.amazonaws.com/'
    if not all(isinstance(image, str) and _IMAGE.fullmatch(image) and image.startswith(prefix) for image in images.values()):
        raise VaultInputsError("Reviewed Vault artifact image does not use the selected private registry.")
    chart = value["chart"]
    if not (isinstance(chart, dict) and set(chart) == {"version", "digest"} and isinstance(chart["version"], str)
            and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", chart["version"]) and isinstance(chart["digest"], str)
            and re.fullmatch(r"sha256:[a-f0-9]{64}", chart["digest"])):
        raise VaultInputsError("Reviewed Vault chart is not pinned.")
    # Canonical JSON binds the reviewed document semantics without reopening
    # the path after the safe JSON read above.
    return value, hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()

def _expected(destination: Path, baseline: dict, artifact: dict, digest: str, discovery: dict) -> dict:
    account, region, name = discovery["aws_account_id"], discovery["aws_region"], discovery["deployment_name"]
    if _value(baseline, "deployment_account_id") != account or _value(baseline, "cluster_name") != name:
        raise VaultInputsError("Baseline output does not match the selected deployment.")
    kms, subnets, repositories = _value(baseline, "vault_unseal_key_arn"), _value(baseline, "private_subnet_ids"), _value(baseline, "private_gitops_ecr_repository_urls")
    if not (isinstance(kms, str) and _KMS.fullmatch(kms) and kms.startswith(f"arn:aws:kms:{region}:{account}:key/")
            and isinstance(subnets, list) and len(subnets) >= 1 and all(isinstance(item, str) and re.fullmatch(r"subnet-[a-z0-9]+", item) for item in subnets)
            and isinstance(repositories, dict) and set(repositories) >= {"vault", "vault_chart", "cert_manager", "cert_manager_chart"}
            and all(isinstance(repositories[key], str) and re.fullmatch(rf"{account}\.dkr\.ecr\.{region}\.amazonaws\.com/[a-z0-9][a-z0-9._/-]*", repositories[key]) for key in ("vault", "vault_chart", "cert_manager", "cert_manager_chart"))):
        raise VaultInputsError("Baseline output lacks a valid Vault KMS, subnet, or private chart context.")
    if not artifact["images"]["bootstrap"].split("@", 1)[0] == repositories["vault"]:
        raise VaultInputsError("Vault bootstrap image is not bound to the baseline private Vault repository.")
    receipt_path = destination.parent / "vault-artifact-mirror-receipt.json"
    receipt = _read(receipt_path, "Verified mirror receipt could not be read safely.")
    if not (isinstance(receipt, dict) and receipt.get("schema_version") == 1 and receipt.get("status") == "verified"
            and all(receipt.get(key) == discovery[field] for key, field in (("aws_account_id", "aws_account_id"), ("aws_region", "aws_region"), ("deployment_name", "deployment_name")))
            and isinstance(receipt.get("artifacts"), dict)):
        raise VaultInputsError("Verified mirror receipt does not bind the selected deployment.")
    index_path = destination.parent / "release" / "rendered" / "installer-artifact-index.json"
    index = _read(index_path, "Materialized installer artifact index could not be read safely.")
    index_digest = hashlib.sha256(index_path.read_bytes()).hexdigest()
    if not (re.fullmatch(r"[0-9a-f]{40}", receipt.get("release_revision", "")) and receipt.get("index_sha256") == index_digest
            and index.get("release_revision") == receipt["release_revision"] and index.get("schema_version") == 1
            and isinstance(index.get("components"), dict) and set(index["components"]) == _INDEX_COMPONENTS):
        raise VaultInputsError("Verified mirror receipt is not bound to the materialized release index.")
    mirrored = receipt["artifacts"]
    required = {"cert-manager-controller", "cert-manager-webhook", "cert-manager-cainjector", "cert-manager-startupapicheck", "cert-manager-chart"}
    if set(mirrored) != _MIRRORED_ARTIFACTS or not required <= set(mirrored):
        raise VaultInputsError("Verified mirror receipt lacks cert-manager platform artifacts.")
    cert_images = {}
    for key, source in (("controller", "cert-manager-controller"), ("webhook", "cert-manager-webhook"), ("cainjector", "cert-manager-cainjector"), ("startupapicheck", "cert-manager-startupapicheck")):
        image = mirrored[source].get("image_ref") if isinstance(mirrored[source], dict) else None
        receipt_digest = mirrored[source].get("manifest_digest") if isinstance(mirrored[source], dict) else None
        source_digest = index["components"].get(source, {}).get("manifest_digest")
        if not isinstance(image, str) or not _IMAGE.fullmatch(image) or not isinstance(source_digest, str) or not re.fullmatch(r"sha256:[a-f0-9]{64}", source_digest) or receipt_digest != source_digest or image != repositories["cert_manager"] + "@" + source_digest:
            raise VaultInputsError("Verified mirror receipt has invalid cert-manager image binding.")
        cert_images[key] = image
    chart_record = mirrored["cert-manager-chart"]
    chart_digest = chart_record.get("manifest_digest") if isinstance(chart_record, dict) else None
    chart_ref = chart_record.get("image_ref") if isinstance(chart_record, dict) else None
    receipt_version = chart_record.get("version") if isinstance(chart_record, dict) else None
    chart_index = index["components"].get("cert-manager-chart", {})
    chart_version = chart_index.get("version") if isinstance(chart_index, dict) else None
    if not isinstance(chart_digest, str) or not re.fullmatch(r"sha256:[a-f0-9]{64}", chart_digest) or not isinstance(chart_ref, str) or chart_ref != repositories["cert_manager_chart"] + "@" + chart_digest or not isinstance(chart_version, str) or receipt_version != chart_version or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", chart_version) or chart_digest != chart_index.get("expected_oci_manifest_digest"):
        raise VaultInputsError("Verified mirror receipt has invalid cert-manager chart binding.")
    tfvars = {"enable_vault_bootstrap_runner": True, "enable_vault_bootstrap_cluster_admin": False,
              "vault_bootstrap_subnet_ids": subnets, "vault_bootstrap_image": artifact["images"]["bootstrap"],
              "vault_chart_version": artifact["chart"]["version"], "vault_chart_manifest_digest": artifact["chart"]["digest"],
              "vault_runtime_images": {key: artifact["images"][key] for key in ("server", "agent", "injector", "audit_relay")},
              "cert_manager_runtime_images": cert_images, "cert_manager_chart_manifest_digest": chart_digest,
              "cert_manager_chart_version": chart_version}
    role = _value(baseline, "vault_role_arn")
    if not isinstance(role, str) or not re.fullmatch(rf"arn:aws:iam::{account}:role/[A-Za-z0-9+=,.@_/-]+", role):
        raise VaultInputsError("Baseline output has an invalid Vault Pod Identity role.")
    context = {"schema_version": 1, "aws_account_id": account, "aws_region": region, "deployment_name": name,
               "vault_unseal_key_arn": kms, "vault_role_arn": role,
               "vault_chart_repository": repositories["vault_chart"], "artifact_sha256": digest,
               "images": artifact["images"], "chart": artifact["chart"], "tfvars": str(destination / "vault-bootstrap.tfvars.json")}
    return {"vault-bootstrap.tfvars.json": tfvars, "vault-bootstrap-context.json": context}

def _baseline_contract(state_dir: Path, discovery: dict) -> tuple[dict, str]:
    inputs = state_dir / "infrastructure-inputs"
    config = _read(inputs / "baseline.tfvars.json", "Original baseline Terraform input could not be read safely.")
    principal = config.get("terraform_apply_role_arn")
    if not isinstance(principal, str):
        raise VaultInputsError("Original baseline Terraform input lacks its backend role binding.")
    try:
        _validate_tree(inputs, expected_inputs(inputs, discovery, principal))
    except InfrastructureError as error:
        raise VaultInputsError("Original infrastructure inputs differ from the completed baseline contract.") from error
    return config, hashlib.sha256(json.dumps(config, sort_keys=True, separators=(",", ":")).encode()).hexdigest()

def _validate(directory: Path, expected: dict) -> None:
    _private(directory, "Vault bootstrap input directory must be private and original.")
    if {item.name for item in directory.iterdir()} != set(expected): raise VaultInputsError("Vault bootstrap inputs are missing or unexpected.")
    for name, wanted in expected.items():
        if json.dumps(_read(directory / name, "Vault bootstrap input could not be read safely."), sort_keys=True) != json.dumps(wanted, sort_keys=True):
            raise VaultInputsError("Vault bootstrap inputs differ from the reviewed deployment context.")

def prepare_vault_inputs(state_dir: Path, discovery: dict, artifacts_path: Path) -> Path:
    _safe_state(state_dir); _private(state_dir / "terraform-work", "Baseline Terraform work directory is unavailable or unsafe.")
    baseline = _read(state_dir / "terraform-work/baseline-output.json", "Baseline output could not be read safely.")
    baseline_config, baseline_config_digest = _baseline_contract(state_dir, discovery)
    artifact, digest = _artifact(artifacts_path, discovery)
    destination = state_dir / "vault-bootstrap-inputs"; expected = _expected(destination, baseline, artifact, digest, discovery)
    expected["vault-bootstrap-context.json"]["baseline_config"] = str(state_dir / "infrastructure-inputs/baseline.tfvars.json")
    expected["vault-bootstrap-context.json"]["baseline_config_sha256"] = baseline_config_digest
    if destination.exists() or destination.is_symlink(): _validate(destination, expected); return destination / "vault-bootstrap.tfvars.json"
    stage = Path(tempfile.mkdtemp(prefix=".vault-bootstrap-inputs-", dir=state_dir)) / "generated"
    try:
        stage.mkdir(mode=0o700)
        for name, value in expected.items():
            path = stage / name; path.write_text(json.dumps(value, sort_keys=True) + "\n"); os.chmod(path, 0o600)
        _validate(stage, expected)
        if destination.exists() or destination.is_symlink(): raise VaultInputsError("Vault bootstrap destination appeared during preparation.")
        publish_directory(stage, destination)
    except OSError as error: raise VaultInputsError("Vault bootstrap inputs could not be prepared safely.") from error
    finally: shutil.rmtree(stage.parent, ignore_errors=True)
    return destination / "vault-bootstrap.tfvars.json"
