#!/usr/bin/env python3
"""Render fail-closed, non-secret cert-manager values from reviewed private ECR digests."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import re
import sys
import tempfile

IMAGE = re.compile(r"^(?P<account>[0-9]{12})\.dkr\.ecr\.(?P<region>[a-z]{2}(?:-gov)?-[a-z]+-[0-9])\.amazonaws\.com/(?P<repository>[a-z0-9][a-z0-9._/-]*)@sha256:(?P<digest>[a-f0-9]{64})$")
TOKENS = ("CONTROLLER", "WEBHOOK", "CAINJECTOR", "STARTUPAPICHECK")
def fail(message: str, code: int = 65) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)
def image_parts(value: str, account: str, region: str) -> tuple[str, str]:
    match = IMAGE.fullmatch(value)
    if not match or match["account"] != account or match["region"] != region:
        fail("each image must be a digest-pinned private ECR image in the selected account and Region")
    return (f"{match['account']}.dkr.ecr.{match['region']}.amazonaws.com/{match['repository']}", match["digest"])
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--aws-account-id", required=True)
    parser.add_argument("--aws-region", required=True)
    parser.add_argument("--controller-image", required=True)
    parser.add_argument("--webhook-image", required=True)
    parser.add_argument("--cainjector-image", required=True)
    parser.add_argument("--startupapicheck-image", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]{12}", args.aws_account_id) or not re.fullmatch(r"[a-z]{2}(?:-gov)?-[a-z]+-[0-9]", args.aws_region):
        fail("invalid AWS account or Region", 64)
    if not args.output.is_absolute() or args.output.exists() or args.output.is_symlink():
        fail("output must be a new absolute non-symlink path")
    if not args.template.is_file() or args.template.is_symlink():
        fail("template must be a regular file")
    parent = args.output.parent
    if not parent.is_dir() or parent.is_symlink() or (parent.stat().st_mode & 0o777) != 0o700:
        fail("output parent must be a private (0700) directory")
    template = args.template.read_text(encoding="utf-8")
    if "106760547719" in template or "REPLACE_WITH_" in template:
        fail("template contains historical or unresolved deployment data")
    supplied = (args.controller_image, args.webhook_image, args.cainjector_image, args.startupapicheck_image)
    replacements: dict[str, str] = {}
    for token, image in zip(TOKENS, supplied, strict=True):
        repository, digest = image_parts(image, args.aws_account_id, args.aws_region)
        replacements[f"__CERT_MANAGER_{token}_REPOSITORY__"] = repository
        replacements[f"__CERT_MANAGER_{token}_TAG__"] = digest
        replacements[f"__CERT_MANAGER_{token}_DIGEST__"] = digest
    rendered = template
    for token, value in replacements.items():
        rendered = rendered.replace(token, value)
    if "__CERT_MANAGER_" in rendered or "REPLACE_WITH_" in rendered:
        fail("rendered values contain unresolved deployment data")
    try:
        fd, staged = tempfile.mkstemp(prefix=".cert-manager-values.", dir=parent)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(rendered)
            handle.flush()
            os.fchmod(handle.fileno(), 0o600)
        os.link(staged, args.output, follow_symlinks=False)
        os.unlink(staged)
    except FileExistsError:
        fail("refusing to overwrite output")
    except OSError as error:
        fail(f"could not safely create output: {error}")
    print(f"PASS rendered non-secret private cert-manager values at {args.output}")
if __name__ == "__main__":
    main()
