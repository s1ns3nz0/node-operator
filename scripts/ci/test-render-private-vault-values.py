# Check objective: Verify fail-closed generic private Vault values rendering.
from __future__ import annotations
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/release/render-private-vault-values.sh"
TEMPLATE = ROOT / "release/vault-values.yaml.example"

class Renderer(unittest.TestCase):
    def render(self, directory, region="ap-northeast-1", account="123456789012", extra=()):
        output = directory / "values.yaml"; image = f"{account}.dkr.ecr.{region}.amazonaws.com/private/vault@sha256:" + "a" * 64
        args = ["bash", str(SCRIPT), "--template", str(TEMPLATE), "--output", str(output), "--aws-account-id", account, "--aws-region", region, "--unseal-key-arn", f"arn:aws:kms:{region}:{account}:key/abcd", "--server-image", image, "--agent-image", image, "--injector-image", image, "--audit-relay-image", image, *extra]
        return subprocess.run(args, text=True, capture_output=True), output
    def test_supported_regions_and_hardening(self):
        with tempfile.TemporaryDirectory() as temp:
            first = Path(temp) / "a"; first.mkdir(mode=0o700)
            result, output = self.render(first); self.assertEqual(result.returncode, 0, result.stderr); text = output.read_text()
            self.assertIn("replicas: 3", text); self.assertIn("auditStorage:", text); self.assertIn("ClusterIP", text); self.assertNotIn("__VAULT_", text); self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            expected_relay = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/private/vault@sha256:" + "a" * 64
            self.assertIn("image: " + expected_relay + "\n", text)
            second = Path(temp) / "b"; second.mkdir(mode=0o700)
            result, output = self.render(second, "ap-northeast-2", "210987654321"); self.assertEqual(result.returncode, 0); self.assertIn("210987654321.dkr.ecr.ap-northeast-2", output.read_text())
    def test_bad_inputs_and_existing_or_symlink_output_preserve_target(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp); os.chmod(directory, 0o700)
            result, output = self.render(directory, extra=("--server-image", "bad")); self.assertNotEqual(result.returncode, 0); self.assertFalse(output.exists())
            output.write_text("keep"); result, _ = self.render(directory); self.assertNotEqual(result.returncode, 0); self.assertEqual(output.read_text(), "keep")
            output.unlink(); victim = directory / "victim"; victim.write_text("keep"); output.symlink_to(victim); result, _ = self.render(directory); self.assertNotEqual(result.returncode, 0); self.assertEqual(victim.read_text(), "keep")
    def test_unresolved_token_has_no_final_output(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp); os.chmod(directory, 0o700); template = directory / "bad.yaml"; template.write_text(TEMPLATE.read_text() + "\nx: __VAULT_UNKNOWN__\n")
            image = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/private/vault@sha256:" + "a" * 64
            result = subprocess.run(["bash", str(SCRIPT), "--template", str(template), "--output", str(directory / "output"), "--aws-account-id", "123456789012", "--aws-region", "ap-northeast-1", "--unseal-key-arn", "arn:aws:kms:ap-northeast-1:123456789012:key/abcd", "--server-image", image, "--agent-image", image, "--injector-image", image, "--audit-relay-image", image], capture_output=True)
            self.assertNotEqual(result.returncode, 0); self.assertFalse((directory / "output").exists())
if __name__ == "__main__": unittest.main()
