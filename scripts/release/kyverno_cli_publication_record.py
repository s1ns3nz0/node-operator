#!/usr/bin/env python3
"""Create the non-secret, digest-bound Kyverno CLI publication record."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import stat
from typing import Any

SHA40 = re.compile(r"^[a-f0-9]{40}$")
SHA256 = re.compile(r"^[a-f0-9]{64}$")
DIGEST = re.compile(r"^sha256:[a-f0-9]{64}$")
ACCOUNT = re.compile(r"^[0-9]{12}$")
REGION = re.compile(r"^ap-northeast-[12]$")
NAME = re.compile(r"^[a-z][a-z0-9-]{1,18}[a-z0-9]$")
RUN = re.compile(r"^[1-9][0-9]*$")
MAX = 1024 * 1024
INPUTS = (".ci/kyverno-cli/Dockerfile", ".ci/kyverno-cli/source-lock.json", ".ci/kyverno-cli/scripts/update-etcd.sh")

class KyvernoPublicationRecordError(ValueError): pass

def _pairs(values: list[tuple[str, Any]]) -> dict[str, Any]:
    result = {}
    for key, value in values:
        if key in result: raise KyvernoPublicationRecordError("duplicate JSON key")
        result[key] = value
    return result

def _read(path: Path) -> Any:
    try:
        info = path.lstat()
        if path.is_symlink() or not stat.S_ISREG(info.st_mode) or info.st_size > MAX: raise KyvernoPublicationRecordError("unsafe input")
        return json.loads(path.read_text(), object_pairs_hook=_pairs)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise KyvernoPublicationRecordError("invalid JSON input") from error

def _file(root: Path, relative: str) -> bytes:
    path = root / relative
    try:
        info = path.lstat()
        if path.is_symlink() or not stat.S_ISREG(info.st_mode) or info.st_size > MAX: raise KyvernoPublicationRecordError("unsafe build input")
        return path.read_bytes()
    except OSError as error: raise KyvernoPublicationRecordError("missing build input") from error

def input_sha256(root: Path) -> str:
    digest = hashlib.sha256()
    for relative in INPUTS:
        digest.update(relative.encode() + b"\0" + hashlib.sha256(_file(root, relative)).digest())
    return digest.hexdigest()

def source(root: Path) -> dict[str, str]:
    lock = _read(root / ".ci/kyverno-cli/source-lock.json")
    if not isinstance(lock, dict) or set(lock) != {"schema_version", "source", "build", "module_update"}: raise KyvernoPublicationRecordError("source lock schema is invalid")
    value = lock.get("source")
    build = lock.get("build")
    if not isinstance(value, dict) or set(value) != {"repository", "tag", "commit"} or value["repository"] != "https://github.com/kyverno/kyverno.git" or not isinstance(value["tag"], str) or not re.fullmatch(r"v[0-9]+(?:\.[0-9]+){1,3}(?:[-+][A-Za-z0-9.-]+)?", value["tag"]) or not SHA40.fullmatch(value["commit"]): raise KyvernoPublicationRecordError("source lock identity is invalid")
    if not isinstance(build, dict) or build.get("target") != "make build-cli VERSION=" + value["tag"] or build.get("platform") != "linux/amd64": raise KyvernoPublicationRecordError("source lock build is invalid")
    try:
        dockerfile = _file(root, ".ci/kyverno-cli/Dockerfile").decode("utf-8")
    except UnicodeDecodeError as error:
        raise KyvernoPublicationRecordError("Dockerfile is invalid") from error
    commits = re.findall(r"^ARG[ \t]+KYVERNO_COMMIT=([a-f0-9]{40})[ \t]*$", dockerfile, re.MULTILINE)
    targets = re.findall(r"\bmake[ \t]+build-cli[ \t]+VERSION=([^ \t\\\r\n]+)", dockerfile)
    origins = re.findall(r"\bgit[ \t]+remote[ \t]+add[ \t]+origin[ \t]+([^ \t\\\r\n]+)", dockerfile)
    if commits != [value["commit"]] or targets != [value["tag"]] or origins != [value["repository"]]: raise KyvernoPublicationRecordError("Dockerfile source defaults differ from source lock")
    return {"repository": value["repository"], "tag": value["tag"], "commit": value["commit"], "platform": "linux/amd64"}

def create_record(root: Path, *, release_revision: str, image_ref: str, manifest_digest: str, run_id: str) -> dict[str, Any]:
    if not SHA40.fullmatch(release_revision) or not DIGEST.fullmatch(manifest_digest) or not RUN.fullmatch(run_id): raise KyvernoPublicationRecordError("publication context is invalid")
    match = re.fullmatch(r"([0-9]{12})\.dkr\.ecr\.(ap-northeast-[12])\.amazonaws\.com/([a-z][a-z0-9-]{1,18}[a-z0-9])-baseline-gitops-nodes@(" + DIGEST.pattern[1:-1] + r")", image_ref)
    if not match or match.group(4) != manifest_digest: raise KyvernoPublicationRecordError("publication target is invalid")
    return {"schema_version": 1, "component": "kyverno-cli", "release_revision": release_revision, "input_sha256": input_sha256(root), "source": source(root), "target": {"aws_account_id": match.group(1), "aws_region": match.group(2), "deployment_name": match.group(3), "repository": match.group(3)+"-baseline-gitops-nodes", "image_ref": image_ref, "manifest_digest": manifest_digest, "platform": "linux/amd64"}, "publication": {"workflow": "image-publish.yml", "run_id": run_id, "invocation": "kyverno-cli-publish"}, "verification": {"method": "scan-cosign-and-provenance", "status": "passed", "scan_passed": True, "cosign_verified": True, "provenance_verified": True}}
