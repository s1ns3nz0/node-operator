# Check objective: Verify fresh Vault TLS ordering without accessing a cluster or secrets.
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/release/prepare-vault-bootstrap-tls.sh"
MOCK = '''#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
with open(os.environ["CALLS"], "a") as f: f.write(" ".join(args) + "\\n")
mode = os.environ["CASE"]
if "rollout" in args and mode == "unready": sys.exit(1)
if "namespace" in args and "get" in args:
    if mode == "api_error": sys.exit(1)
    if mode != "new": print("namespace/vault")
if "statefulset" in args:
    if mode == "stateful_error": sys.exit(1)
    if mode == "existing": print("statefulset.apps/vault")
if "secret" in args:
    assert args[-2:] == ["-o", "name"], "Secret data must never be fetched"
    print("secret/vault-tls")
'''


class TLSBootstrapTests(unittest.TestCase):
    def invoke(self, mode):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            binary = directory / "kubectl"
            binary.write_text(MOCK)
            binary.chmod(0o755)
            manifest = directory / "certificates.yaml"
            manifest.write_text("# trusted fixture\n")
            calls = directory / "calls"
            result = subprocess.run(
                ["bash", str(SCRIPT), "--manifest", str(manifest)],
                env={**os.environ, "PATH": str(directory) + ":" + os.environ["PATH"],
                     "CALLS": str(calls), "CASE": mode},
                capture_output=True, text=True, timeout=10,
            )
            return result, calls.read_text().splitlines() if calls.exists() else []

    def test_ready_tls_is_name_only_and_existing_namespace_preserved(self):
        result, calls = self.invoke("ready")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sum(command.startswith("apply -f ") for command in calls), 1)
        self.assertFalse(any("create namespace" in command or "label namespace" in command for command in calls))
        self.assertEqual(sum("wait --for=condition=Ready certificate/" in command for command in calls), 2)
        self.assertIn("-n vault get secret vault-tls -o name", calls)

    def test_new_namespace_precedes_certificate_application(self):
        result, calls = self.invoke("new")
        self.assertEqual(result.returncode, 0, result.stderr)
        create = next(i for i, command in enumerate(calls) if "create namespace vault" in command)
        apply = next(i for i, command in enumerate(calls) if command.startswith("apply -f "))
        self.assertLess(create, apply)
        self.assertTrue(any("label namespace vault" in command and "enforce=restricted" in command for command in calls))

    def test_unready_existing_or_unreachable_never_mutates(self):
        for mode in ("unready", "existing", "api_error", "stateful_error"):
            with self.subTest(mode=mode):
                result, calls = self.invoke(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(command.startswith(("apply ", "create ", "label ")) for command in calls))


if __name__ == "__main__":
    unittest.main()
