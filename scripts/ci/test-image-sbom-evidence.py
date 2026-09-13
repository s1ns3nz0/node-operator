#!/usr/bin/env python3
"""Offline tests for local Docker-archive SBOM evidence receipts."""
import importlib.util
import json
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/ci/image_sbom_evidence.py"
SPEC = importlib.util.spec_from_file_location("image_sbom_evidence", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)
REVISION = "a" * 40
CONFIG = "sha256:" + "b" * 64


def sbom(archive_sha: str) -> dict:
    return {
        "bomFormat": "CycloneDX", "specVersion": "1.5",
        "metadata": {"tools": [{"vendor": "anchore", "name": "syft", "version": "test"}], "component": {"type": "file", "name": "subject", "version": "sha256:" + archive_sha}},
        "components": [
            {"type": "file", "name": "/usr/bin/example", "hashes": [{"alg": "SHA-256", "content": "a" * 64}]},
            {"type": "operating-system", "name": "debian", "version": "13"},
            {"type": "library", "name": "openssl", "version": "3.0", "purl": "pkg:apk/alpine/openssl@3.0"},
        ],
    }


class SbomEvidenceTests(unittest.TestCase):
    def test_actual_publication_opa_queries_fail_closed(self):
        # Exercise the query from each real publisher, not a test-only policy call.
        temp, archive, document, receipt = self.make()
        with temp:
            MODULE.create(archive, document, REVISION, CONFIG, "release-build", receipt)
            valid = json.loads(receipt.read_text())
            for publisher in ("publish-scanner-image.sh", "publish-toolchain-image.sh"):
                source = (ROOT / "scripts/release" / publisher).read_text()
                queries = re.findall(r"'(true = data\.nodeoperator\.image_sbom\.allow)'", source)
                self.assertEqual(len(queries), 1, publisher)
                denied = dict(valid, claims=dict(valid["claims"], signature=True))
                for value, allowed in ((valid, True), (denied, False), ({}, False)):
                    receipt.write_text(json.dumps(value))
                    result = subprocess.run([
                        "opa", "eval", "--fail", "--format", "json", "--data",
                        str(ROOT / "policy/image_sbom.rego"), "--input", str(receipt), queries[0],
                    ], capture_output=True, text=True, timeout=30)
                    self.assertEqual(result.returncode == 0, allowed, publisher + result.stdout + result.stderr)

    def make(self):
        temp = tempfile.TemporaryDirectory()
        base = Path(temp.name); archive = base / "image.tar"; archive.write_bytes(b"synthetic docker archive")
        digest = MODULE._sha256(archive, MODULE.MAX_ARCHIVE); document = base / "sbom.json"; document.write_text(json.dumps(sbom(digest)))
        return temp, archive, document, base / "receipt.json"

    def test_create_verify_and_cli(self):
        temp, archive, document, receipt = self.make()
        with temp:
            result = subprocess.run([sys.executable, str(SCRIPT), "create", "--archive", str(archive), "--sbom", str(document), "--revision", REVISION, "--image-config-digest", CONFIG, "--subject", "release-build", "--output", str(receipt)], capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([sys.executable, str(SCRIPT), "verify", "--archive", str(archive), "--sbom", str(document), "--revision", REVISION, "--image-config-digest", CONFIG, "--subject", "release-build", "--receipt", str(receipt)], capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_tampering_or_invalid_schema_fails_closed(self):
        temp, archive, document, receipt = self.make()
        with temp:
            MODULE.create(archive, document, REVISION, CONFIG, "release-build", receipt)
            archive.write_bytes(b"tampered")
            with self.assertRaises(MODULE.EvidenceError):
                MODULE.verify(archive, document, REVISION, CONFIG, "release-build", receipt)
            archive.write_bytes(b"synthetic docker archive")
            document.write_bytes(b"{}")
            with self.assertRaises(MODULE.EvidenceError):
                MODULE.verify(archive, document, REVISION, CONFIG, "release-build", receipt)
            document.write_text(json.dumps(sbom(MODULE._sha256(archive, MODULE.MAX_ARCHIVE))))
            with self.assertRaises(MODULE.EvidenceError):
                MODULE.verify(archive, document, "A" * 40, CONFIG, "release-build", receipt)
            receipt.write_text("{}")
            with self.assertRaises(MODULE.EvidenceError):
                MODULE.verify(archive, document, REVISION, CONFIG, "release-build", receipt)
            document.write_text('{"bomFormat":"CycloneDX","bomFormat":"CycloneDX"}')
            with self.assertRaises(MODULE.EvidenceError):
                MODULE.create(archive, document, REVISION, CONFIG, "release-build", receipt)

    def test_symlink_and_missing_component_identity_are_rejected(self):
        temp, archive, document, receipt = self.make()
        with temp:
            bad = sbom(MODULE._sha256(archive, MODULE.MAX_ARCHIVE)); bad["components"][2].pop("purl"); document.write_text(json.dumps(bad))
            with self.assertRaises(MODULE.EvidenceError):
                MODULE.create(archive, document, REVISION, CONFIG, "release-build", receipt)
            link = document.parent / "link.tar"; link.symlink_to(archive)
            with self.assertRaises(MODULE.EvidenceError):
                MODULE.create(link, document, REVISION, CONFIG, "release-build", receipt)

    def test_file_hash_must_be_a_valid_sha256(self):
        temp, archive, document, receipt = self.make()
        with temp:
            for hashes in ([{}], [{"alg": "SHA-256", "content": "invalid"}], []):
                bad = sbom(MODULE._sha256(archive, MODULE.MAX_ARCHIVE))
                bad["components"][0]["hashes"] = hashes
                document.write_text(json.dumps(bad))
                with self.assertRaises(MODULE.EvidenceError):
                    MODULE.create(archive, document, REVISION, CONFIG, "release-build", receipt)


if __name__ == "__main__":
    unittest.main()
