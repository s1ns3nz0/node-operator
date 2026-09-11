# Check objective: Verify private cert-manager rendering and fresh-only deployment guards with bounded command mocks.
from __future__ import annotations
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
RENDERER = ROOT / "scripts/release/render-private-cert-manager-values.py"
TEMPLATE = ROOT / "release/cert-manager-values.yaml.example"
DEPLOYER = ROOT / "scripts/release/deploy-private-cert-manager.sh"
ACCOUNT, REGION = "123456789012", "us-west-2"
def image(name: str, digest: str) -> str:
    return f"{ACCOUNT}.dkr.ecr.{REGION}.amazonaws.com/private/{name}@sha256:{digest * 64}"

class PrivateCertManager(unittest.TestCase):
    def render(self, directory: Path, extra: tuple[str, ...] = ()):
        output = directory / "values.yaml"
        command = ["python3", str(RENDERER), "--template", str(TEMPLATE), "--output", str(output), "--aws-account-id", ACCOUNT, "--aws-region", REGION,
                   "--controller-image", image("controller", "a"), "--webhook-image", image("webhook", "b"), "--cainjector-image", image("cainjector", "c"), "--startupapicheck-image", image("startup", "d"), *extra]
        return subprocess.run(command, text=True, capture_output=True), output
    def test_render_is_portable_hardened_and_digest_pinned(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); os.chmod(directory, 0o700)
            result, output = self.render(directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            text = output.read_text()
            self.assertNotIn("__CERT_MANAGER_", text); self.assertNotIn("106760547719", text)
            self.assertEqual(text.count(f"repository: {ACCOUNT}.dkr.ecr.{REGION}.amazonaws.com/"), 4)
            self.assertEqual(text.count('digest: "sha256:'), 4)
            self.assertIn("readOnlyRootFilesystem: true", text)
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
    def test_render_rejects_mismatch_placeholders_and_overwrites(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); os.chmod(directory, 0o700)
            result, output = self.render(directory, ("--webhook-image", image("webhook", "b").replace(REGION, "us-east-1")))
            self.assertNotEqual(result.returncode, 0); self.assertFalse(output.exists())
            output.write_text("keep"); result, _ = self.render(directory)
            self.assertNotEqual(result.returncode, 0); self.assertEqual(output.read_text(), "keep")
            output.unlink(); bad = directory / "bad.yaml"; bad.write_text(TEMPLATE.read_text() + "\nx: __CERT_MANAGER_UNKNOWN__\n")
            result, _ = self.render(directory, ("--template", str(bad)))
            self.assertNotEqual(result.returncode, 0); self.assertFalse(output.exists())
    def deploy(self, mode: str, values: str | None = None):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); binary = base / "bin"; binary.mkdir(); calls = base / "calls"
            calls.touch()
            mock = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name, args = Path(sys.argv[0]).name, sys.argv[1:]
with open(os.environ["CALLS"], "a") as output: output.write(json.dumps([name] + args) + "\\n")
mode = os.environ["MODE"]
if name == "helm" and args[:1] == ["status"]: sys.exit(0 if mode == "release" else 1)
if name == "helm": sys.exit(1 if mode == "helm_failure" else 0)
if "get" in args and mode == "existing": print("deployment.apps/cert-manager")
if "rollout" in args and mode == "rollout_failure": sys.exit(1)
if "wait" in args and mode == "crd_failure": sys.exit(1)
'''
            for name in ("helm", "kubectl"):
                target = binary / name; target.write_text(mock); target.chmod(0o700)
            path = base / "values.yaml"
            if values is None:
                values = TEMPLATE.read_text()
                for token, name, digest in (("CONTROLLER", "controller", "a"), ("WEBHOOK", "webhook", "b"), ("CAINJECTOR", "cainjector", "c"), ("STARTUPAPICHECK", "startup", "d")):
                    values = values.replace(f"__CERT_MANAGER_{token}_REPOSITORY__", f"{ACCOUNT}.dkr.ecr.{REGION}.amazonaws.com/private/{name}").replace(f"__CERT_MANAGER_{token}_TAG__", digest * 64).replace(f"__CERT_MANAGER_{token}_DIGEST__", digest * 64)
            path.write_text(values)
            result = subprocess.run(["bash", str(DEPLOYER), "--chart", f"oci://{ACCOUNT}.dkr.ecr.{REGION}.amazonaws.com/private/cert-manager@sha256:" + "e" * 64, "--values", str(path)], text=True, capture_output=True, env=dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"], CALLS=str(calls), MODE=mode))
            return result, [json.loads(line) for line in calls.read_text().splitlines()]
    def test_deploy_is_fresh_atomic_and_verifies_workloads_and_crds(self):
        result, calls = self.deploy("fresh")
        self.assertEqual(result.returncode, 0, result.stderr)
        helm = next(call for call in calls if call[0] == "helm" and "upgrade" in call)
        for required in ("--create-namespace", "--atomic", "--wait", "--set", "crds.enabled=true"): self.assertIn(required, helm)
        self.assertEqual(len([call for call in calls if "rollout" in call]), 3)
        self.assertEqual(len([call for call in calls if "wait" in call]), 2)
    def test_deploy_rejects_existing_bad_values_and_failures(self):
        for mode in ("existing", "release", "helm_failure", "rollout_failure", "crd_failure"):
            with self.subTest(mode=mode):
                result, calls = self.deploy(mode); self.assertNotEqual(result.returncode, 0)
                if mode in ("existing", "release"): self.assertFalse(any(call[0] == "helm" and "upgrade" in call for call in calls))
        pinned = TEMPLATE.read_text()
        for token, name, digest in (("CONTROLLER", "controller", "a"), ("WEBHOOK", "webhook", "b"), ("CAINJECTOR", "cainjector", "c"), ("STARTUPAPICHECK", "startup", "d")):
            pinned = pinned.replace(f"__CERT_MANAGER_{token}_REPOSITORY__", f"{ACCOUNT}.dkr.ecr.{REGION}.amazonaws.com/private/{name}").replace(f"__CERT_MANAGER_{token}_TAG__", digest * 64).replace(f"__CERT_MANAGER_{token}_DIGEST__", digest * 64)
        public = pinned.replace(f"{ACCOUNT}.dkr.ecr.{REGION}.amazonaws.com/private/controller", "quay.io/jetstack/cert-manager", 1)
        missing = pinned.replace('  digest: "sha256:' + "a" * 64 + '"\n', "", 1)
        mismatch = pinned.replace('digest: "sha256:' + "a" * 64 + '"', 'digest: "sha256:' + "b" * 64 + '"', 1)
        nonhex = pinned.replace('tag: "' + "a" * 64 + '"', 'tag: "not-a-digest"', 1)
        for invalid in (public, missing, mismatch, nonhex):
            result, calls = self.deploy("fresh", invalid)
            self.assertNotEqual(result.returncode, 0); self.assertFalse(any(call[0] == "helm" and "upgrade" in call for call in calls))

if __name__ == "__main__":
    unittest.main()
