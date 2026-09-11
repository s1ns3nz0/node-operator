# Check objective: Verify bootstrap transport routing, CA validation and temporary-session cleanup.
"""Local contract checks for the guarded Vault transport wrapper."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = (ROOT / "scripts/ops/with-private-vault.sh").read_text()


class PrivateVaultTransportContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); root = Path(self.temp.name)
        self.repo = root / "repo"; ops = self.repo / "scripts/ops"; ops.mkdir(parents=True)
        shutil.copy2(ROOT / "scripts/ops/with-private-vault.sh", ops / "with-private-vault.sh")
        (ops / "with-private-eks.sh").write_text('#!/bin/sh\nshift; exec "$@"\n'); os.chmod(ops / "with-private-eks.sh", 0o755)
        self.bin = root / "bin"; self.bin.mkdir(); self.log = root / "log"; self.tmp = root / "tmp"; self.tmp.mkdir()
        self.write("kubectl", '#!/bin/sh\necho "$@" >> "$LOG"\ncase "$*" in *port-forward*) while :; do sleep 1; done;; *) printf "%s\\n" "$CA";; esac\n')
        self.write("openssl", '#!/bin/sh\ngrep -q CERTIFICATE "$3"\n')
        self.write("nc", '#!/bin/sh\nexit 0\n')
    def tearDown(self): self.temp.cleanup()
    def write(self, name, value):
        p=self.bin/name; p.write_text(value); os.chmod(p,0o755)
    def invoke(self, *args, child='exit 0', ca='-----BEGIN CERTIFICATE-----\nx\n-----END CERTIFICATE-----'):
        env=os.environ | {'PATH':str(self.bin)+':'+os.environ['PATH'], 'TMPDIR':str(self.tmp), 'LOG':str(self.log), 'CA':ca}
        return subprocess.run([str(self.repo/'scripts/ops/with-private-vault.sh'), *args, '--', 'sh','-c',child], env=env, text=True, capture_output=True)

    def test_real_default_and_bootstrap_routes(self):
        self.assertEqual(self.invoke(child='exit 0').returncode, 0)
        self.assertIn('port-forward service/vault-active', self.log.read_text())
        self.assertFalse(list(self.tmp.glob('node-operator-vault-*')))
        self.log.unlink()
        self.assertEqual(self.invoke('--bootstrap', child='exit 0').returncode, 0)
        self.assertIn('port-forward pod/vault-0', self.log.read_text())
        self.assertFalse(list(self.tmp.glob('node-operator-vault-*')))

    def test_real_bad_ca_blocks_child_and_child_exit_is_preserved(self):
        result=self.invoke(child='touch "$TMPDIR/child"', ca='bad')
        self.assertNotEqual(result.returncode, 0); self.assertFalse((self.tmp/'child').exists())
        self.assertEqual(self.invoke(child='exit 42').returncode, 42)

    def test_invalid_flag_never_reaches_outer_wrapper(self):
        result=subprocess.run([str(self.repo/'scripts/ops/with-private-vault.sh'),'--nope'], text=True, capture_output=True)
        self.assertEqual(result.returncode, 64)

    def test_default_and_bootstrap_targets_are_fixed(self):
        self.assertIn('target="service/vault-active"', SCRIPT)
        self.assertIn('target="pod/vault-0"', SCRIPT)
        self.assertIn('[ "${1:-}" = --bootstrap ]', SCRIPT)
        self.assertNotIn('port-forward "$1"', SCRIPT)

    def test_requires_separator_and_preserves_tls_verification(self):
        self.assertIn('[ "${1:-}" = -- ] || usage', SCRIPT)
        self.assertIn('VAULT_ADDR="https://127.0.0.1:${vault_port}"', SCRIPT)
        self.assertIn('VAULT_CACERT="$ca_file"', SCRIPT)
        self.assertIn('VAULT_TLS_SERVER_NAME="vault.vault.svc"', SCRIPT)
        self.assertIn('openssl x509 -in "$ca_file" -noout', SCRIPT)

    def test_cleanup_individual_files_and_signal_wait(self):
        self.assertIn('unlink "$port_log" || cleanup_status=1', SCRIPT)
        self.assertIn('unlink "$ca_file" || cleanup_status=1', SCRIPT)
        self.assertIn('wait "$port_pid"', SCRIPT)
        self.assertIn('trap signal_cleanup TERM HUP INT', SCRIPT)

    def test_no_init_or_secret_read(self):
        self.assertNotIn('vault operator init', SCRIPT)
        self.assertNotIn('kubectl get secret', SCRIPT)


if __name__ == "__main__":
    unittest.main()
