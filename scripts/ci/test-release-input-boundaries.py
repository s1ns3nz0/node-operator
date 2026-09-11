# Check objective: Keep JSON and HCL infrastructure inputs behind the same ownership boundaries.
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "scripts/release/node-operator-release.sh").read_text()
FUNCTIONS = "reject_privileged_baseline_inputs() {" + SOURCE.split(
    "reject_privileged_baseline_inputs() {", 1)[1].split("\nwrite_backend_config() {", 1)[0]


@unittest.skipUnless(shutil.which("jq") and shutil.which("rg"), "release runtime requires jq and rg")
class InputBoundaries(unittest.TestCase):
    def check_input(self, content, suffix=".json"):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / ("baseline" + suffix)
            path.write_text(content)
            script = ('set -euo pipefail\nfail() { exit 1; }\n' + FUNCTIONS +
                      '\nrequire_nonsecret_file "$1"\nreject_privileged_baseline_inputs "$1"\nreject_derived_network_inputs "$1"\n')
            return subprocess.run(["bash", "-c", script, "test", str(path)],
                                  capture_output=True, text=True).returncode

    def test_disabled_or_absent_separate_phases_are_allowed(self):
        self.assertEqual(self.check_input('{}'), 0)
        self.assertEqual(self.check_input(json.dumps({
            "enable_temporary_ssm_ops_host": False,
            "enable_vault_bootstrap_cluster_admin": False,
            "enable_argocd_bootstrap_cluster_admin": False})), 0)

    def test_privileged_json_values_are_rejected(self):
        for field in ("enable_temporary_ssm_ops_host", "enable_vault_bootstrap_cluster_admin",
                      "enable_argocd_bootstrap_cluster_admin"):
            for value in (True, "true", 1, {}, []):
                with self.subTest(field=field, value=value):
                    self.assertNotEqual(self.check_input(json.dumps({field: value})), 0)

    def test_derived_network_fields_cannot_override_outputs(self):
        for field in ("network_source", "foundation_network", "hoodi_nat_gateway_id"):
            self.assertNotEqual(self.check_input(json.dumps({field: None})), 0)

    def test_invalid_json_and_multiple_documents_fail(self):
        for content in ("", "{", "[]", "null", '{}\n{}'):
            self.assertNotEqual(self.check_input(content), 0)

    def test_hcl_boundaries_remain_enforced(self):
        self.assertEqual(self.check_input('enable_temporary_ssm_ops_host = false\n', '.tfvars'), 0)
        for content in ('enable_temporary_ssm_ops_host = true\n',
                        'enable_vault_bootstrap_cluster_admin = true\n',
                        'network_source = "existing"\n'):
            self.assertNotEqual(self.check_input(content, '.tfvars'), 0)

    def test_credentials_are_rejected_without_printing_values(self):
        for key in ("vault_token", "recovery-key", "mnemonic", "keystore", "private_key", "AWS_SECRET_ACCESS_KEY"):
            self.assertNotEqual(self.check_input(json.dumps({"nested": [{key: "not-a-real-secret"}]})), 0)

    def test_generated_phase_context_is_bound(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            context = {"aws_account_id": "123456789012", "aws_region": "ap-northeast-1",
                       "name": "installer-test", "availability_zones": ["ap-northeast-1a", "ap-northeast-1c"]}
            paths = [root / (name + ".json") for name in ("manifest", "bootstrap", "foundation", "baseline")]
            phases = [dict(context) for _ in paths]
            phases[2]["network_mode"] = "fresh"

            def execute():
                for path, phase in zip(paths, phases):
                    path.write_text(json.dumps(phase))
                script = 'set -euo pipefail\nfail() { exit 1; }\n' + FUNCTIONS + '\nverify_generated_input_context "$1" "$2" "$3" "$4"\n'
                return subprocess.run(["bash", "-c", script, "test", *map(str, paths)], capture_output=True).returncode

            self.assertEqual(execute(), 0)
            for index, field, changed in ((1, "aws_account_id", "999999999999"),
                                          (3, "aws_account_id", "999999999999"),
                                          (1, "name", "different"), (2, "aws_region", "ap-northeast-2"),
                                          (3, "availability_zones", ["ap-northeast-2a", "ap-northeast-2c"]),
                                          (2, "network_mode", "existing")):
                original = phases[index][field]
                phases[index][field] = changed
                self.assertNotEqual(execute(), 0)
                phases[index][field] = original


if __name__ == "__main__":
    unittest.main()
