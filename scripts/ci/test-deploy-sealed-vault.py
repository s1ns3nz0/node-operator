#!/usr/bin/env python3
# Check objective: Exercise fresh sealed Vault installation without initialization or existing-server mutation.
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SealedVault(unittest.TestCase):
    def run_case(self, mode):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            binary = base / "bin"
            binary.mkdir()
            mock = """#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['CALLS'], 'a') as out:
    out.write(json.dumps([name] + args) + '\\n')
mode = os.environ['MODE']
if name == 'helm':
    sys.exit(1 if mode == 'helm_failure' else 0)
if 'get' in args:
    if mode == 'existing': print('statefulset.apps/vault')
elif 'wait' in args:
    sys.exit(1 if mode == 'wait_failure' else 0)
elif 'exec' in args:
    if mode == 'invalid_json': print('invalid')
    else: print(json.dumps({'initialized': mode == 'initialized', 'sealed': True, 'storage_type': 'raft'}))
    sys.exit(1 if mode == 'transport_failure' else 2)
"""
            for name in ("kubectl", "helm"):
                target = binary / name
                target.write_text(mock)
                target.chmod(0o700)
            values = base / "values.yaml"
            values.write_text("fixture: true\n")
            calls = base / "calls"
            result = subprocess.run([
                "bash", str(ROOT / "scripts/release/deploy-sealed-vault.sh"),
                "--chart", "oci://123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/vault@sha256:" + "a" * 64,
                "--values", str(values),
            ], env=dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"],
                        CALLS=str(calls), MODE=mode, TMPDIR=str(base)), capture_output=True, text=True)
            invoked = [json.loads(line) for line in calls.read_text().splitlines()]
            self.assertFalse(list(base.glob("sealed-vault-check.*")))
            self.assertFalse(any("init" in command for command in invoked))
            return result, invoked

    def test_three_sealed_servers_are_accepted_without_ready_wait(self):
        result, calls = self.run_case("fresh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len([call for call in calls if "exec" in call]), 3)
        for call in calls:
            if "exec" in call:
                pod = call[call.index("exec") + 1]
                self.assertIn("VAULT_ADDR=https://" + pod + ".vault-internal:8200", call)
                self.assertIn("VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt", call)
                self.assertFalse(any("SKIP_VERIFY" in argument for argument in call))
        helm = next(call for call in calls if call[0] == "helm")
        self.assertNotIn("--atomic", helm)
        self.assertNotIn("--wait", helm)
        waits = [call for call in calls if "wait" in call]
        self.assertEqual(len(waits), 6)
        for create, running in zip(waits[::2], waits[1::2]):
            self.assertIn("--for=create", create)
            self.assertIn("--for=jsonpath={.status.phase}=Running", running)

    def test_existing_server_is_never_upgraded(self):
        result, calls = self.run_case("existing")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[0] == "helm" for call in calls))

    def test_failures_cannot_report_bootstrap_success(self):
        for mode in ("helm_failure", "wait_failure", "initialized", "invalid_json", "transport_failure"):
            with self.subTest(mode=mode):
                result, _ = self.run_case(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("PASS:", result.stdout)


if __name__ == "__main__":
    unittest.main()
