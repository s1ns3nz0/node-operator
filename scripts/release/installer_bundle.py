#!/usr/bin/env python3
"""Read-only verification for a downloaded node-operator release bundle.

This module deliberately does not extract archives or verify a Vault Transit
signature.  The latter happens in the private signing boundary; here we only
check that its recorded, already-verified result is bound to the downloaded
bytes and provenance.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import tarfile
from typing import Any


ARCHIVE_NAME = "node-operator-release-bundle.tar"
RELEASE_FILES = frozenset(
    {
        ARCHIVE_NAME,
        "node-operator-release-bundle.sha256",
        "manifest.json",
        "provenance-input.json",
        "release-verification.json",
        "sbom.cyclonedx.json",
    }
)
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
TRANSIT_SIGNATURE_RE = re.compile(r"^vault:v[0-9]+:[A-Za-z0-9+/=_-]+$")
MAX_JSON_BYTES = 4 * 1024 * 1024
MAX_MANIFEST_ENTRIES = 10_000
MAX_TAR_MEMBERS = 10_001  # manifest plus the maximum number of listed files
MAX_TAR_MEMBER_BYTES = 64 * 1024 * 1024
MAX_TAR_TOTAL_BYTES = 256 * 1024 * 1024


class ReleaseVerificationError(ValueError):
    """The downloaded evidence is malformed or does not describe its bytes."""


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ReleaseVerificationError("duplicate JSON object key")
        result[key] = value
    return result


def _load_json(path: Path) -> Any:
    try:
        size = path.lstat().st_size
    except OSError as error:
        raise ReleaseVerificationError(f"cannot read {path.name}: {error}") from error
    if size > MAX_JSON_BYTES:
        raise ReleaseVerificationError(f"JSON file is too large: {path.name}")
    try:
        data = path.read_bytes()
    except OSError as error:
        raise ReleaseVerificationError(f"cannot read {path.name}: {error}") from error
    if len(data) > MAX_JSON_BYTES:
        raise ReleaseVerificationError(f"JSON file is too large: {path.name}")
    try:
        return json.loads(data.decode("utf-8"), object_pairs_hook=_reject_duplicate_keys)
    except (UnicodeDecodeError, json.JSONDecodeError, ReleaseVerificationError) as error:
        raise ReleaseVerificationError(f"invalid JSON in {path.name}: {error}") from error


def _canonical_digest(value: Any) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return "sha256:" + hashlib.sha256(encoded).hexdigest()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _require_regular(path: Path) -> None:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError as error:
        raise ReleaseVerificationError(f"missing required file: {path.name}") from error
    if not stat.S_ISREG(mode):
        raise ReleaseVerificationError(f"required path is not a regular file: {path.name}")


def _safe_name(name: object) -> str:
    if not isinstance(name, str) or not name or "\x00" in name or "\\" in name:
        raise ReleaseVerificationError("entry path must be a non-empty POSIX relative path")
    path = PurePosixPath(name)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise ReleaseVerificationError("unsafe entry path")
    if str(path) != name:
        raise ReleaseVerificationError("non-canonical entry path")
    return name


def _exact_object(value: Any, keys: set[str], description: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise ReleaseVerificationError(f"{description} has an unexpected schema")
    return value


def _validate_manifest(manifest: Any, *, outer: bool) -> dict[str, Any]:
    required = {"schema_version", "artifact", "source_revision", "entries"}
    if not isinstance(manifest, dict) or set(manifest) != required:
        raise ReleaseVerificationError("manifest has an unexpected schema")
    if manifest["schema_version"] != "v1" or not isinstance(manifest["source_revision"], str) or not SHA40_RE.fullmatch(manifest["source_revision"]):
        raise ReleaseVerificationError("manifest schema version or source revision is invalid")
    artifact_keys = {"name", "media_type", "digest"} if outer else {"name", "media_type"}
    artifact = _exact_object(manifest["artifact"], artifact_keys, "manifest artifact")
    if artifact["name"] != ARCHIVE_NAME or artifact["media_type"] != "application/x-tar":
        raise ReleaseVerificationError("manifest artifact identity is invalid")
    if outer and (not isinstance(artifact["digest"], str) or not DIGEST_RE.fullmatch(artifact["digest"])):
        raise ReleaseVerificationError("manifest artifact digest is invalid")
    if not isinstance(manifest["entries"], list):
        raise ReleaseVerificationError("manifest entries is not a list")
    if len(manifest["entries"]) > MAX_MANIFEST_ENTRIES:
        raise ReleaseVerificationError("manifest has too many entries")
    paths: set[str] = set()
    for entry in manifest["entries"]:
        entry = _exact_object(entry, {"path", "sha256", "size"}, "manifest entry")
        name = _safe_name(entry["path"])
        if name in paths:
            raise ReleaseVerificationError("duplicate manifest entry")
        paths.add(name)
        if not isinstance(entry["sha256"], str) or not SHA256_RE.fullmatch(entry["sha256"]):
            raise ReleaseVerificationError("manifest entry has an invalid SHA-256")
        if not isinstance(entry["size"], int) or isinstance(entry["size"], bool) or entry["size"] < 0:
            raise ReleaseVerificationError("manifest entry has an invalid size")
        if entry["size"] > MAX_TAR_MEMBER_BYTES:
            raise ReleaseVerificationError("manifest entry is too large")
    return manifest


def _validate_tar(archive: Path, manifest: dict[str, Any]) -> None:
    expected_entries = {entry["path"]: entry for entry in manifest["entries"]}
    manifest_bytes: bytes | None = None
    seen: set[str] = set()
    total_size = 0
    try:
        with tarfile.open(archive, "r:") as tar:
            for member in tar:
                if len(seen) >= MAX_TAR_MEMBERS:
                    raise ReleaseVerificationError("tar has too many members")
                name = _safe_name(member.name)
                if name in seen:
                    raise ReleaseVerificationError("duplicate tar entry")
                seen.add(name)
                if not member.isfile():
                    raise ReleaseVerificationError("tar contains a non-regular entry")
                if member.size > MAX_TAR_MEMBER_BYTES:
                    raise ReleaseVerificationError("tar member is too large")
                total_size += member.size
                if total_size > MAX_TAR_TOTAL_BYTES:
                    raise ReleaseVerificationError("tar contents are too large")
                extracted = tar.extractfile(member)
                if extracted is None:
                    raise ReleaseVerificationError("cannot inspect tar entry")
                digest_state = hashlib.sha256()
                contents = bytearray() if name == "bundle-manifest.json" else None
                for chunk in iter(lambda: extracted.read(1024 * 1024), b""):
                    digest_state.update(chunk)
                    if contents is not None:
                        contents.extend(chunk)
                digest = digest_state.hexdigest()
                if name == "bundle-manifest.json":
                    manifest_bytes = bytes(contents or b"")
                    continue
                expected = expected_entries.get(name)
                if expected is None or member.size != expected["size"] or digest != expected["sha256"]:
                    raise ReleaseVerificationError("tar entry does not match manifest")
    except (tarfile.TarError, OSError) as error:
        raise ReleaseVerificationError(f"invalid tar archive: {error}") from error
    if seen != set(expected_entries) | {"bundle-manifest.json"}:
        raise ReleaseVerificationError("tar entries do not exactly match the manifest")
    if manifest_bytes is None:
        raise ReleaseVerificationError("tar is missing bundle-manifest.json")
    if len(manifest_bytes) > MAX_JSON_BYTES:
        raise ReleaseVerificationError("embedded bundle manifest is too large")
    try:
        embedded = json.loads(manifest_bytes.decode("utf-8"), object_pairs_hook=_reject_duplicate_keys)
    except (UnicodeDecodeError, json.JSONDecodeError, ReleaseVerificationError) as error:
        raise ReleaseVerificationError(f"invalid embedded bundle manifest: {error}") from error
    embedded = _validate_manifest(embedded, outer=False)
    if (embedded["source_revision"] != manifest["source_revision"] or embedded["entries"] != manifest["entries"] or
            embedded["artifact"] != {"name": ARCHIVE_NAME, "media_type": "application/x-tar"}):
        raise ReleaseVerificationError("embedded bundle manifest is not bound to outer manifest")


def verify_bundle(archive: str | Path, manifest: dict[str, Any], expected_bundle_digest: str | None = None) -> dict[str, Any]:
    """Verify original tar contents against the outer manifest without extraction."""
    archive_path = Path(archive)
    _require_regular(archive_path)
    actual_digest = "sha256:" + _sha256_file(archive_path)
    if expected_bundle_digest is not None and actual_digest != expected_bundle_digest:
        raise ReleaseVerificationError("tar digest does not match the outer manifest")
    _validate_tar(archive_path, manifest)
    return {"source_revision": manifest["source_revision"], "bundle_digest": actual_digest, "manifest": manifest}


def verify_release(download_dir: str | Path) -> dict[str, Any]:
    """Verify the complete fresh downloaded release evidence and tar contents.

    This checks recorded signer evidence bindings only; it does *not* perform
    offline cryptographic verification of the Transit signature.
    """
    directory = Path(download_dir)
    if directory.is_symlink() or not directory.is_dir():
        raise ReleaseVerificationError("download directory must be a non-symlink directory")
    present = {item.name for item in directory.iterdir()}
    if present != RELEASE_FILES:
        raise ReleaseVerificationError("download directory must contain exactly the six release assets")
    for name in RELEASE_FILES:
        _require_regular(directory / name)
    outer = _validate_manifest(_load_json(directory / "manifest.json"), outer=True)
    archive = directory / ARCHIVE_NAME
    checksum = (directory / "node-operator-release-bundle.sha256").read_text(encoding="utf-8")
    expected_checksum = f"{outer['artifact']['digest']}  {ARCHIVE_NAME}\n"
    if checksum != expected_checksum:
        raise ReleaseVerificationError("checksum file is not the canonical manifest-bound record")
    provenance = _load_json(directory / "provenance-input.json")
    verification = _load_json(directory / "release-verification.json")
    sbom = _load_json(directory / "sbom.cyclonedx.json")
    digest = outer["artifact"]["digest"]
    source_revision = outer["source_revision"]
    dependency = {"uri": "git+node-operator", "digest": {"gitCommit": source_revision}}
    try:
        dependencies = provenance["predicate"]["buildDefinition"]["resolvedDependencies"]
        subject = provenance["subject"]
        builder = provenance["predicate"]["runDetails"]["builder"]["id"]
    except (KeyError, TypeError) as error:
        raise ReleaseVerificationError("provenance has an unexpected schema") from error
    if (provenance.get("_type") != "https://in-toto.io/Statement/v1" or provenance.get("predicateType") != "https://slsa.dev/provenance/v1" or
            subject != [{"name": ARCHIVE_NAME, "digest": {"sha256": digest[7:]}}] or dependency not in dependencies or
            builder != "local://node-operator/scripts/ci/build-release-bundle.sh"):
        raise ReleaseVerificationError("provenance is not bound to the manifest")
    provenance_digest = "sha256:" + _sha256_file(directory / "provenance-input.json")
    try:
        valid_record = (verification["schema_version"] == "v1" and verification["artifact"] == {"name": ARCHIVE_NAME, "digest": digest} and
                        verification["provenance"]["sha256"] == provenance_digest and verification["provenance"]["subject_digest"] == digest and
                        verification["provenance"]["source_revision"] == source_revision and verification["provenance"]["builder_id"] == builder and
                        verification["transit"]["key"] == "node-operator-release" and verification["transit"]["verified"] is True and
                        isinstance(verification["transit"]["signature"], str) and TRANSIT_SIGNATURE_RE.fullmatch(verification["transit"]["signature"]) and
                        verification["signer"] == {"auth_method": "aws", "vault_role": "release-signer"} and
                        isinstance(verification["codebuild"]["build_id"], str) and bool(verification["codebuild"]["build_id"]))
    except (KeyError, TypeError):
        valid_record = False
    if not valid_record:
        raise ReleaseVerificationError("release verification record is not bound to this release")
    try:
        sbom_component = sbom["metadata"]["component"]
    except (KeyError, TypeError) as error:
        raise ReleaseVerificationError("SBOM has an unexpected schema") from error
    if sbom.get("bomFormat") != "CycloneDX" or sbom_component.get("name") != ARCHIVE_NAME or sbom_component.get("version") != digest:
        raise ReleaseVerificationError("SBOM is not bound to the manifest artifact")
    verify_bundle(archive, outer, digest)
    return {"release_sha": source_revision, "bundle_digest": digest, "manifest_digest": _canonical_digest(outer), "manifest": outer}


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only node-operator release bundle verifier")
    parser.add_argument("download_dir")
    arguments = parser.parse_args()
    try:
        context = verify_release(arguments.download_dir)
    except ReleaseVerificationError as error:
        parser.error(str(error))
    print(json.dumps({key: value for key, value in context.items() if key != "manifest"}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
