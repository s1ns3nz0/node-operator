#!/usr/bin/env python3
"""Exercise cleanup outcomes using synthetic CLI responses, without live access."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class BootstrapCleanup(unittest.TestCase):
    def invoke(self, bootstrap_rc=0, revoke_rc=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "lib").mkdir()
            wrapper = root / "recover-and-bootstrap-hoodi-vault-v2.sh"
            shutil.copy2(ROOT / "scripts/ops" / wrapper.name, wrapper)
            (root / "lib/vault-recovery-auth.sh").write_text(
                "vault_recovery_auth_preflight() { :; }\n"
                "vault_recovery_decode_generated_root() { printf synthetic; }\n")
            for name in ("bootstrap-node-operator-vault-v2.sh",
                         "bootstrap-hoodi-engine-api-vault.sh",
                         "bootstrap-hoodi-validator-runtime-vault.sh"):
                path = root / name
                path.write_text('#!/bin/bash\nexit "$BOOTSTRAP_RC"\n')
                path.chmod(0o700)
            vault = root / "vault"
            vault.write_text("""#!/bin/bash
case "$*" in
  *"generate-root -status"*) echo '{"started":false}' ;;
  *"generate-root -init"*) echo '{"nonce":"n","otp":"o","required":1}' ;;
  *"generate-root -nonce="*) echo '{"complete":true,"encoded_token":"e"}' ;;
  "token revoke -self") echo revoked >> "$EVENTS"; exit "$REVOKE_RC" ;;
  *) exit 64 ;;
esac
""")
            vault.chmod(0o700)
            events = root / "events"
            result = subprocess.run(
                ["bash", str(wrapper), "--validator-set", "hoodi-001"],
                input="synthetic-share\n", text=True, capture_output=True,
                env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}",
                     "PRIVATE_VAULT_SESSION": "1", "BOOTSTRAP_RC": str(bootstrap_rc),
                     "REVOKE_RC": str(revoke_rc), "EVENTS": str(events)})
            self.assertEqual(events.read_text(), "revoked\n")
            self.assertNotIn("synthetic", result.stdout + result.stderr)
            return result

    def test_success_only_after_revocation(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0)
        self.assertIn("generated root token revoked", result.stdout)

    def test_revocation_failure_cannot_report_success(self):
        result = self.invoke(revoke_rc=1)
        self.assertEqual(result.returncode, 70)
        self.assertNotIn("PASS", result.stdout)
        self.assertIn("CRITICAL", result.stderr)

    def test_bootstrap_failure_still_revokes_and_preserves_failure(self):
        result = self.invoke(bootstrap_rc=42)
        self.assertEqual(result.returncode, 42)
        self.assertNotIn("PASS", result.stdout)


if __name__ == "__main__":
    unittest.main()
