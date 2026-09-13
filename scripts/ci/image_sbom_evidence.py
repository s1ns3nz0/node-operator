#!/usr/bin/env python3
"""Create or verify a local, unsigned Docker-archive CycloneDX evidence receipt."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys

SHA256 = re.compile(r"[0-9a-f]{64}$")
REVISION = re.compile(r"[0-9a-f]{40}$")
DIGEST = re.compile(r"sha256:[0-9a-f]{64}$")
MAX_ARCHIVE = 4 * 1024 * 1024 * 1024
MAX_SBOM = 16 * 1024 * 1024
MAX_RECEIPT = 1024 * 1024


class EvidenceError(ValueError):
    """An input cannot provide fail-closed SBOM evidence."""


def _open_regular(path: Path, maximum: int):
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as error:
        raise EvidenceError(f"cannot open {path}") from error
    info = os.fstat(descriptor)
    if not stat.S_ISREG(info.st_mode) or info.st_size > maximum:
        os.close(descriptor)
        raise EvidenceError(f"unsafe file {path}")
    return os.fdopen(descriptor, "rb")


def _bytes(path: Path, maximum: int) -> bytes:
    try:
        with _open_regular(path, maximum) as stream:
            content = stream.read(maximum + 1)
    except OSError as error:
        raise EvidenceError(f"cannot read {path}") from error
    if len(content) > maximum:
        raise EvidenceError(f"unsafe file {path}")
    return content


def _sha256(path: Path, maximum: int) -> str:
    digest = hashlib.sha256()
    try:
        with _open_regular(path, maximum) as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise EvidenceError(f"cannot read {path}") from error
    return digest.hexdigest()


def _string(value: object) -> bool:
    return isinstance(value, str) and bool(value) and len(value) <= 512 and not any(ord(char) < 32 for char in value)


def _unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result = {}
    for key, value in pairs:
        if key in result:
            raise EvidenceError("JSON contains duplicate keys")
        result[key] = value
    return result


def _validate_sbom(path: Path, archive_sha256: str) -> str:
    raw = _bytes(path, MAX_SBOM)
    try:
        bom = json.loads(raw, object_pairs_hook=_unique_object)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceError("SBOM is malformed JSON") from error
    if not isinstance(bom, dict) or bom.get("bomFormat") != "CycloneDX" or not _string(bom.get("specVersion")):
        raise EvidenceError("SBOM is not a CycloneDX document")
    metadata = bom.get("metadata")
    if not isinstance(metadata, dict) or not isinstance(metadata.get("tools"), (list, dict)) or not metadata["tools"]:
        raise EvidenceError("SBOM lacks generator tools")
    component = metadata.get("component")
    if not isinstance(component, dict) or component.get("version") != f"sha256:{archive_sha256}":
        raise EvidenceError("SBOM metadata component does not bind the Docker archive digest")
    components = bom.get("components")
    if not isinstance(components, list) or not components:
        raise EvidenceError("SBOM lacks components")
    for item in components:
        if not isinstance(item, dict) or not _string(item.get("name")):
            raise EvidenceError("SBOM component lacks name")
        kind = item.get("type")
        # Syft emits file inventory entries with a path and content hashes, but
        # no package version. Treat them as file evidence, not package records.
        if kind == "file":
            if not isinstance(item.get("hashes"), list) or not any(
                isinstance(value, dict) and value.get("alg") == "SHA-256"
                and isinstance(value.get("content"), str) and SHA256.fullmatch(value["content"])
                for value in item["hashes"]
            ):
                raise EvidenceError("SBOM file component lacks hash evidence")
            continue
        if not _string(item.get("version")):
            raise EvidenceError("SBOM component lacks version")
        # Syft's valid CycloneDX distribution descriptor (for example Debian)
        # carries only type/name/version. Libraries and container images still
        # need a package identifier, but an operating-system descriptor does not.
        if kind in {"library", "container"} and not (_string(item.get("purl")) or _string(item.get("cpe"))):
            raise EvidenceError("SBOM component lacks package identity evidence")
    return hashlib.sha256(raw).hexdigest()


def _validate_args(archive: Path, sbom: Path, revision: str, image_config_digest: str, subject: str) -> tuple[str, str]:
    if not REVISION.fullmatch(revision) or not DIGEST.fullmatch(image_config_digest) or not _string(subject):
        raise EvidenceError("invalid revision, image config digest, or subject")
    archive_sha256 = _sha256(archive, MAX_ARCHIVE)
    return archive_sha256, _validate_sbom(sbom, archive_sha256)


def create(archive: Path, sbom: Path, revision: str, image_config_digest: str, subject: str, output: Path) -> dict:
    archive_sha256, sbom_sha256 = _validate_args(archive, sbom, revision, image_config_digest, subject)
    if output.exists() or output.is_symlink() or not output.parent.is_dir() or output.parent.is_symlink():
        raise EvidenceError("unsafe receipt output")
    receipt = {
        "schema_version": 1,
        "stage": "build",
        "subject": subject,
        "source_revision": revision,
        "docker_archive_sha256": archive_sha256,
        "image_config_digest": image_config_digest,
        "sbom_sha256": sbom_sha256,
        "claims": {"signature": False, "registry_manifest_digest": False, "sca": False},
    }
    try:
        with output.open("x", encoding="utf-8") as stream:
            json.dump(receipt, stream, sort_keys=True, separators=(",", ":"))
            stream.write("\n")
    except OSError as error:
        raise EvidenceError("cannot create receipt") from error
    return receipt


def verify(archive: Path, sbom: Path, revision: str, image_config_digest: str, subject: str, receipt_path: Path) -> None:
    archive_sha256, sbom_sha256 = _validate_args(archive, sbom, revision, image_config_digest, subject)
    try:
        receipt = json.loads(_bytes(receipt_path, MAX_RECEIPT), object_pairs_hook=_unique_object)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceError("receipt is malformed JSON") from error
    expected = {
        "schema_version": 1, "stage": "build", "subject": subject, "source_revision": revision,
        "docker_archive_sha256": archive_sha256, "image_config_digest": image_config_digest, "sbom_sha256": sbom_sha256,
        "claims": {"signature": False, "registry_manifest_digest": False, "sca": False},
    }
    if receipt != expected:
        raise EvidenceError("receipt does not exactly bind supplied evidence")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    command = parser.add_subparsers(dest="command", required=True)
    for name in ("create", "verify"):
        action = command.add_parser(name)
        action.add_argument("--archive", type=Path, required=True)
        action.add_argument("--sbom", type=Path, required=True)
        action.add_argument("--revision", required=True)
        action.add_argument("--image-config-digest", required=True)
        action.add_argument("--subject", required=True)
        action.add_argument("--output" if name == "create" else "--receipt", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "create":
            create(args.archive, args.sbom, args.revision, args.image_config_digest, args.subject, args.output)
        else:
            verify(args.archive, args.sbom, args.revision, args.image_config_digest, args.subject, args.receipt)
    except EvidenceError as error:
        print(f"image SBOM evidence rejected: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
