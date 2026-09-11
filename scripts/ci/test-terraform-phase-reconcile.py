"""Prove resumed completed phases are checked without applying resource changes."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "scripts/release/node-operator-release.sh").read_text()
FUNCTION = "verify_completed_phase() {" + SOURCE.split("verify_completed_phase() {", 1)[1].split("\nzero_apply() {", 1)[0]


@unittest.skipUnless(shutil.which("jq"), "release runtime requires jq")
class PhaseReconcileTests(unittest.TestCase):
    def exercise(self, plan_code=0, saved='{"vpc":"vpc-123"}', actual='{"vpc":"vpc-123"}', output_code=0, missing_module=False):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            module = directory / "module"
            if not missing_module:
                module.mkdir()
            checkpoint = directory / "output.json"
            checkpoint.write_text(saved)
            calls = directory / "calls"
            environment = os.environ.copy()
            environment.update(PLAN_CODE=str(plan_code), OUTPUT_CODE=str(output_code), ACTUAL=actual, CALLS=str(calls))
            script = '''set -euo pipefail
umask 077
fail() { printf '%s\\n' "$*" >&2; exit 1; }
terraform() {
  printf '%s\\n' "$2" >> "$CALLS"
  case "$2" in
    plan)
      [ "$#" = 5 ] && [ "$3" = -input=false ] && [ "$4" = -detailed-exitcode ] && [ "$5" = -var-file=/config ] || return 99
      return "$PLAN_CODE" ;;
    output)
      [ "$#" = 4 ] && [ "$3" = -json ] && [ "$4" = network ] || return 99
      printf '%s' "$ACTUAL"; return "$OUTPUT_CODE" ;;
    *) return 99 ;;
  esac
}
''' + FUNCTION + '\nverify_completed_phase "$1" /config "$2" network\n'
            result = subprocess.run(["bash", "-c", script, "test", str(module), str(checkpoint)], env=environment, capture_output=True, text=True)
            commands = calls.read_text().splitlines() if calls.exists() else []
            self.assertNotIn("apply", commands)
            self.assertEqual(checkpoint.read_text(), saved)
            self.assertEqual(list(directory.glob("*.verify.*")), [])
            return result, commands

    def test_no_drift_and_matching_output_can_resume(self):
        result, calls = self.exercise()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["plan", "output"])

    def test_drift_and_plan_errors_stop_before_output(self):
        for code in (1, 2, 130):
            result, calls = self.exercise(plan_code=code)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(calls, ["plan"])

    def test_invalid_checkpoint_or_missing_module_never_calls_terraform(self):
        for options in ({"saved": ""}, {"saved": "{}"}, {"saved": "[]"}, {"missing_module": True}):
            result, calls = self.exercise(**options)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(calls, [])

    def test_changed_malformed_or_failed_output_is_not_accepted(self):
        for options in ({"actual": '{"vpc":"other"}'}, {"actual": ""}, {"actual": '{}\n{}'}, {"output_code": 1}):
            result, _ = self.exercise(**options)
            self.assertNotEqual(result.returncode, 0)

    def test_saved_bootstrap_and_foundation_are_both_reconciled(self):
        self.assertIn('verify_completed_phase "$bootstrap_module" "$bootstrap_config" "$bootstrap_output" backend', SOURCE)
        self.assertIn('verify_completed_phase "$foundation_module" "$foundation_config" "$foundation_output" network', SOURCE)


if __name__ == "__main__":
    unittest.main()
