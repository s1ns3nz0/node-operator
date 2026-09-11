# Check objective: Verify publisher records are emitted only after exact digest verification and cannot overwrite unsafe paths.
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PUBLISHER = ROOT / "scripts/release/publish-toolchain-image.sh"

class Records(unittest.TestCase):
    def run_toolchain(self, mode="ok", existing=False, private=True, revision=None):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); artifacts = base / "artifact"; artifacts.mkdir()
            dockerfile = base / "Dockerfile"; dockerfile.write_text("FROM scratch\n")
            expected = hashlib.sha256((hashlib.sha256(dockerfile.read_bytes()).hexdigest() + "\n").encode()).hexdigest()
            (artifacts / "toolchain-input.sha256").write_text(expected)
            (artifacts / "toolchain-image.tar").write_text("fixture")
            output_parent = base / "output"; output_parent.mkdir(mode=0o700)
            if not private: os.chmod(output_parent, 0o755)
            output = output_parent / "record.json"
            if existing: output.write_text("keep")
            binary = base / "bin"; binary.mkdir()
            mock = '''#!/usr/bin/env python3
import os, sys
args=sys.argv[1:]
if args[:2] == ["image", "inspect"]: print(os.environ["EXPECTED"])
elif args[:3] == ["buildx", "imagetools", "inspect"]:
 print("sha256:" + ("z" if os.environ["MODE"] == "bad_digest" else "a") * 64)
elif args[:1] == ["push"] and os.environ["MODE"] == "push_failure": sys.exit(9)
'''
            target = binary / "docker"; target.write_text(mock); target.chmod(0o700)
            result = subprocess.run(["bash", str(PUBLISHER)], cwd=ROOT, text=True, capture_output=True, env=dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"], DOCKERFILE=str(dockerfile), IMAGE="ghcr.io/example/toolchain", IMAGE_NAME="toolchain", GITHUB_SHA=revision or "b"*40, GITHUB_WORKFLOW="Release Images", GITHUB_RUN_ID="123", GITHUB_RUN_ATTEMPT="1", REGISTRY_TOKEN="token", REGISTRY_USERNAME="user", TOOLCHAIN_ARTIFACT_DIR=str(artifacts), PUBLICATION_RECORD_OUTPUT=str(output), EXPECTED=expected, MODE=mode))
            return result, output.read_text() if output.exists() else None
    def test_exact_record_is_atomic_private_and_bound(self):
        result, content = self.run_toolchain()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        record = json.loads(content)
        self.assertEqual(record["release_revision"], "b"*40)
        self.assertEqual(record["manifest_digest"], "sha256:" + "a"*64)
        self.assertEqual(record["image_ref"], "ghcr.io/example/toolchain@sha256:" + "a"*64)
        self.assertEqual(record["build_revision"], "b"*40)
        self.assertEqual(record["verification"], {"method": "input-hash-and-registry-digest", "status": "passed"})
    def test_failed_push_bad_digest_existing_or_unsafe_parent_emit_no_record(self):
        for options in ({"mode": "push_failure"}, {"mode": "bad_digest"}, {"existing": True}, {"private": False}):
            with self.subTest(options=options):
                result, content = self.run_toolchain(**options)
                self.assertNotEqual(result.returncode, 0)
                if options.get("existing"): self.assertEqual(content, "keep")
                else: self.assertIsNone(content)
    def test_malformed_revision_cannot_emit_record(self):
        result, content = self.run_toolchain(revision="not-a-sha")
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(content)

class RelayContract(unittest.TestCase):
    def test_relay_record_is_after_cosign_slsa_verification(self):
        text = (ROOT / "scripts/release/publish-vault-audit-relay.sh").read_text()
        record = text.index('component:"vault-audit-relay"')
        self.assertGreater(record, text.index('cosign verify-attestation --type slsaprovenance1'))
        self.assertGreater(record, text.index('verify-release-scan-attestation.sh'))
        self.assertIn('verification:{method:"cosign-and-slsa",status:"passed"}', text)
        self.assertIn('ln "$stage" "$record_output"', text)

if __name__ == "__main__":
    unittest.main()
