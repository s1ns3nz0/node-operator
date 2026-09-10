#!/usr/bin/env python3
"""Exercise the actual shell renderers, then reject modified manifests."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("verifier", ROOT / "scripts/ops/verify-validator-cutover-rendering.py")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class Rendering(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        approved = json.loads((ROOT / ".ci/validator/approved-client-images.json").read_text())
        image = next(item["private_image"] for item in approved["images"]
                     if item.get("stage_approved") and item.get("release_channel") in
                     ("upstream-mirror", "manual-native-mtls"))
        registry = image.split("/")[0]
        account, _, _, region, *_ = registry.split(".")
        cls.key = "0x" + "ab" * 48
        cls.images = {"WEB3SIGNER_IMAGE": registry + "/signer@sha256:" + "a" * 64,
                      "POSTGRES_IMAGE": registry + "/postgres@sha256:" + "b" * 64,
                      "SIGNING_FENCE_IMAGE": registry + "/node-operator-baseline-validator-fence@sha256:" + "c" * 64}
        base = ["--validator-set", "hoodi-001", "--aws-account-id", account, "--aws-region", region]
        with tempfile.TemporaryDirectory() as directory:
            runtime = Path(directory) / "runtime.yaml"
            client = Path(directory) / "client.yaml"
            subprocess.run(["bash", str(ROOT / "scripts/ops/render-hoodi-validator-runtime.sh"),
                            *base, "--web3signer-image", registry + "/signer@sha256:" + "a" * 64,
                            "--postgres-image", registry + "/postgres@sha256:" + "b" * 64,
                            "--output", str(runtime)], check=True, capture_output=True)
            subprocess.run(["bash", str(ROOT / "scripts/ops/render-hoodi-validator-client.sh"),
                            *base, "--validator-public-key", cls.key, "--prysm-validator-image", image,
                            "--signing-fence-image", registry + "/node-operator-baseline-validator-fence@sha256:" + "c" * 64,
                            "--kubernetes-api-cidr", "172.20.0.1/32", "--output", str(client)],
                           check=True, capture_output=True)
            cls.runtime, cls.client = runtime.read_text(), client.read_text()

    def test_actual_renderer_output(self):
        verifier.validate(self.runtime, self.client, "hoodi-001", self.key, self.images)

    def test_runtime_changes_rejected(self):
        for old, new in [("replicas: 0", "replicas: 1"), ("port: 5432", "port: 9999"),
                         ("mountPath: /var/lib/postgresql/data", "mountPath: /lost-history"),
                         ("serviceAccountName:", "otherServiceAccountName:")]:
            with self.subTest(old=old):
                modified = self.runtime.replace(old, new)
                self.assertNotEqual(modified, self.runtime)
                with self.assertRaises(ValueError):
                    verifier.validate(modified, self.client, "hoodi-001", self.key, self.images)

    def test_fence_or_client_changes_rejected(self):
        for old, new in [("replicas: 0", "replicas: 1"), ("port: 9000", "port: 9001"),
                         ("172.20.0.1/32", "0.0.0.0/0")]:
            with self.subTest(old=old):
                modified = self.client.replace(old, new)
                self.assertNotEqual(modified, self.client)
                with self.assertRaises(ValueError):
                    verifier.validate(self.runtime, modified, "hoodi-001", self.key, self.images)

    def test_wrong_key_rejected(self):
        with self.assertRaises(ValueError):
            verifier.validate(self.runtime, self.client, "hoodi-001", "0x" + "cd" * 48, self.images)

    def test_runtime_image_changes_rejected(self):
        for key, original in self.images.items():
            with self.subTest(image=key), self.assertRaises(ValueError):
                changed = original.rsplit(":", 1)[0] + ":" + "d" * 64
                verifier.validate(self.runtime.replace(original, changed), self.client.replace(original, changed),
                                  "hoodi-001", self.key, self.images)


if __name__ == "__main__":
    unittest.main()
