"""Verify that failed Terraform output never publishes a completion checkpoint."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "scripts/release/node-operator-release.sh").read_text()
FUNCTION = SOURCE.split("capture_terraform_output() {", 1)[1].split("\nzero_apply() {", 1)[0]
FUNCTION = "capture_terraform_output() {" + FUNCTION


@unittest.skipUnless(shutil.which("jq"), "jq is required by the release entrypoint")
class OutputCheckpointTests(unittest.TestCase):
    def run_capture(self, directory, contents, exit_code=0, named=True):
        environment = os.environ.copy()
        environment.update(TEST_CONTENTS=contents, TEST_EXIT=str(exit_code))
        script = """set -euo pipefail
umask 077
fail() { printf '%s\\n' "$*" >&2; exit 1; }
terraform() {
  [ "$1" = '-chdir=/module' ] && [ "$2" = output ] && [ "$3" = -json ] || return 91
  printf '%s' "$TEST_CONTENTS"
  return "$TEST_EXIT"
}
""" + FUNCTION + '\ncapture_terraform_output /module "$1" "${2:-}"\n'
        return subprocess.run(["bash", "-c", script, "test", str(directory / "output.json"), "backend" if named else ""], env=environment, capture_output=True, text=True)

    def test_success_publishes_private_json_for_named_and_all_outputs(self):
        for named in (True, False):
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory)
                result = self.run_capture(path, '{"bucket":"example"}', named=named)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((path / "output.json").read_text(), '{"bucket":"example"}')
                self.assertEqual((path / "output.json").stat().st_mode & 0o777, 0o600)
                self.assertEqual(list(path.glob("*.pending.*")), [])

    def test_failed_or_invalid_output_never_creates_checkpoint(self):
        for contents, code in [("", 1), ('{"partial":true}', 1), ("invalid", 0), ("{}", 0), ("[]", 0), ("null", 0), ('{"a":1}\n{"b":2}', 0)]:
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory)
                self.assertNotEqual(self.run_capture(path, contents, code).returncode, 0)
                self.assertFalse((path / "output.json").exists())
                self.assertEqual(list(path.glob("*.pending.*")), [])

    def test_failure_preserves_prior_checkpoint(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            checkpoint = path / "output.json"
            checkpoint.write_text('{"previous":true}')
            self.assertNotEqual(self.run_capture(path, "", 1).returncode, 0)
            self.assertEqual(checkpoint.read_text(), '{"previous":true}')

    def test_symlink_destination_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            target = path / "protected"
            target.write_text("unchanged")
            (path / "output.json").symlink_to(target)
            self.assertNotEqual(self.run_capture(path, '{"new":true}').returncode, 0)
            self.assertEqual(target.read_text(), "unchanged")

    def test_all_three_phase_outputs_use_atomic_capture(self):
        for expression in (
            'capture_terraform_output "$bootstrap_module" "$bootstrap_output" backend',
            'capture_terraform_output "$foundation_module" "$foundation_output" network',
            'capture_terraform_output "$baseline_module" "$baseline_output"',
        ):
            self.assertIn(expression, SOURCE)


if __name__ == "__main__":
    unittest.main()
