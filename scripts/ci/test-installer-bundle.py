#!/usr/bin/env python3
"""Synthetic, offline tests for scripts/release/installer_bundle.py."""

import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import sys
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("installer_bundle", ROOT / "scripts/release/installer_bundle.py")
assert SPEC and SPEC.loader
bundle = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = bundle
SPEC.loader.exec_module(bundle)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class InstallerBundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = Path(tempfile.mkdtemp())
        self.download = self.temp / "download"
        self.download.mkdir()
        self.revision = "0" * 40
        self.contents = {"rendered/example.yaml": b"apiVersion: v1\n", "source/release.txt": b"review me\n"}
        self._write_release()

    def tearDown(self):
        shutil.rmtree(self.temp)

    def _manifest(self):
        return {"schema_version": "v1", "artifact": {"name": bundle.ARCHIVE_NAME, "media_type": "application/x-tar"}, "source_revision": self.revision,
                "entries": [{"path": name, "sha256": sha(data), "size": len(data)} for name, data in sorted(self.contents.items())]}

    def _write_tar(self, extra=None, symlink=False):
        archive = self.download / bundle.ARCHIVE_NAME
        manifest_bytes = (json.dumps(self._manifest()) + "\n").encode()
        with tarfile.open(archive, "w") as tar:
            values = {**self.contents, "bundle-manifest.json": manifest_bytes}
            if extra:
                values.update(extra)
            for name, data in values.items():
                item = tarfile.TarInfo(name)
                item.size = len(data)
                tar.addfile(item, io.BytesIO(data))
            if symlink:
                item = tarfile.TarInfo("bad-link")
                item.type = tarfile.SYMTYPE
                item.linkname = "target"
                tar.addfile(item)
        return archive

    def _write_release(self):
        inner = self._manifest()
        archive = self._write_tar()
        digest = "sha256:" + sha(archive.read_bytes())
        outer = {**inner, "artifact": {**inner["artifact"], "digest": digest}}
        (self.download / "manifest.json").write_text(json.dumps(outer) + "\n")
        (self.download / "node-operator-release-bundle.sha256").write_text(f"{digest}  {bundle.ARCHIVE_NAME}\n")
        provenance = {"_type": "https://in-toto.io/Statement/v1", "subject": [{"name": bundle.ARCHIVE_NAME, "digest": {"sha256": digest[7:]}}], "predicateType": "https://slsa.dev/provenance/v1", "predicate": {"buildDefinition": {"resolvedDependencies": [{"uri": "git+node-operator", "digest": {"gitCommit": self.revision}}]}, "runDetails": {"builder": {"id": "local://node-operator/scripts/ci/build-release-bundle.sh"}}}}
        raw = json.dumps(provenance).encode()
        (self.download / "provenance-input.json").write_bytes(raw)
        verification = {"schema_version": "v1", "artifact": {"name": bundle.ARCHIVE_NAME, "digest": digest}, "provenance": {"sha256": "sha256:" + sha(raw), "subject_digest": digest, "source_revision": self.revision, "builder_id": "local://node-operator/scripts/ci/build-release-bundle.sh"}, "transit": {"key": "node-operator-release", "signature": "vault:v1:fixture", "verified": True}, "signer": {"auth_method": "aws", "vault_role": "release-signer"}, "codebuild": {"build_id": "fixture"}}
        (self.download / "release-verification.json").write_text(json.dumps(verification))
        sbom = {"bomFormat": "CycloneDX", "metadata": {"component": {"name": bundle.ARCHIVE_NAME, "version": digest}}}
        (self.download / "sbom.cyclonedx.json").write_text(json.dumps(sbom))

    def test_valid_release_returns_tar_digest_and_canonical_manifest_digest(self):
        context = bundle.verify_release(self.download)
        self.assertEqual(context["release_sha"], self.revision)
        self.assertEqual(context["bundle_digest"], "sha256:" + sha((self.download / bundle.ARCHIVE_NAME).read_bytes()))
        self.assertTrue(context["manifest_digest"].startswith("sha256:"))

    def test_corrupt_tar_is_rejected(self):
        with (self.download / bundle.ARCHIVE_NAME).open("ab") as handle:
            handle.write(b"corrupt")
        with self.assertRaises(bundle.ReleaseVerificationError):
            bundle.verify_release(self.download)

    def test_traversal_manifest_entry_is_rejected(self):
        manifest = self.download / "manifest.json"
        value = json.loads(manifest.read_text())
        value["entries"][0]["path"] = "../escape"
        manifest.write_text(json.dumps(value))
        with self.assertRaises(bundle.ReleaseVerificationError):
            bundle.verify_release(self.download)

    def test_duplicate_json_key_is_rejected(self):
        (self.download / "manifest.json").write_text('{"schema_version":"v1","schema_version":"v1"}')
        with self.assertRaises(bundle.ReleaseVerificationError):
            bundle.verify_release(self.download)

    def test_tar_symlink_is_rejected(self):
        archive = self._write_tar(symlink=True)
        manifest = self._manifest()
        outer = {**manifest, "artifact": {**manifest["artifact"], "digest": "sha256:" + sha(archive.read_bytes())}}
        with self.assertRaises(bundle.ReleaseVerificationError):
            bundle.verify_bundle(archive, outer, outer["artifact"]["digest"])


if __name__ == "__main__":
    unittest.main()
