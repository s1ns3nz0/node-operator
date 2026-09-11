# Check objective: Recover missing phase outputs without repeating infrastructure mutation.
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "scripts/release/node-operator-release.sh").read_text()
FUNCTION = "recover_missing_phase_output() {" + SOURCE.split(
    "recover_missing_phase_output() {", 1)[1].split("\nzero_apply() {", 1)[0]


class PartialRecovery(unittest.TestCase):
    def exercise(self, code=0, state='{"resources":[{}]}', existing=False, query_failure=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            module = root / "module"
            module.mkdir()
            output = root / "output.json"
            if existing:
                output.write_text("original")
            env = os.environ.copy()
            env.update(PLAN_CODE=str(code), STATE=state, QUERY_FAILURE=str(int(query_failure)))
            script = '''set -euo pipefail
fail() { printf '%s\\n' "$*" >&2; exit 1; }
capture_state() { printf '%s' "$STATE" > "$2"; }
terraform() {
  [ "$2" = plan ] && [ "$3" = -input=false ] && [ "$4" = -detailed-exitcode ] || exit 99
  return "$PLAN_CODE"
}
capture_terraform_output() {
  [ "$QUERY_FAILURE" = 0 ] || exit 1
  printf '%s' '{"recovered":true}' > "$2"
}
''' + FUNCTION + '\nrecover_missing_phase_output "$1" /config "$2" backend\n'
            result = subprocess.run(["bash", "-c", script, "test", str(module), str(output)],
                                    env=env, capture_output=True, text=True)
            return result.returncode, output.read_text() if output.exists() else None

    def test_unchanged_phase_recovers_missing_checkpoint(self):
        self.assertEqual(self.exercise(), (0, '{"recovered":true}'))

    def test_remaining_changes_and_query_errors_do_not_publish(self):
        for code in (1, 2, 130):
            result, output = self.exercise(code=code)
            self.assertNotEqual(result, 0)
            self.assertIsNone(output)
        self.assertNotEqual(self.exercise(query_failure=True)[0], 0)

    def test_empty_state_and_existing_checkpoint_are_not_adopted(self):
        self.assertNotEqual(self.exercise(state='{"resources":[]}')[0], 0)
        result, output = self.exercise(existing=True)
        self.assertNotEqual(result, 0)
        self.assertEqual(output, "original")

    def test_both_phase_recovery_calls_are_connected(self):
        for phase in ("bootstrap", "foundation"):
            self.assertIn(f'recover_missing_phase_output "${phase}_module"', SOURCE)
        self.assertNotIn("use a new work directory", SOURCE)


if __name__ == "__main__":
    unittest.main()
