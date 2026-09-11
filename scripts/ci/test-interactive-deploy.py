# Check objective: Exercise installer start, status and resume without cloud calls or credentials.
"""Exercise the installer command path without cloud calls or credentials."""
import contextlib
import importlib
import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "release"))
cli = importlib.import_module("interactive_deploy")
RELEASE = {"release_sha": "a" * 40, "bundle_digest": "sha256:" + "b" * 64}
DISCOVERY = {"aws_profile": "test", "aws_account_id": "123456789012", "aws_region": "ap-northeast-1", "deployment_name": "test-node"}


class InstallerCommandTests(unittest.TestCase):
    def invoke(self, directory, command, extra=()):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = cli.run([command, "--state-dir", str(directory), *extra])
        return result, json.loads(output.getvalue())

    def test_start_status_resume_and_context_binding(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(sys.modules, {"installer_bundle": types.SimpleNamespace(verify_release=lambda _: RELEASE)}), patch.object(cli, "discover", return_value=DISCOVERY) as discover:
            directory = Path(temporary) / "state"
            options = ["--release-dir", temporary, "--aws-profile", "test", "--aws-region", "ap-northeast-1", "--name", "test-node"]
            _, result = self.invoke(directory, "start", options)
            self.assertFalse(result["deployment_complete"])
            count = discover.call_count
            _, status = self.invoke(directory, "status")
            self.assertEqual(discover.call_count, count)
            self.assertEqual(status["stages"]["preflight"]["status"], "awaiting_input")
            self.invoke(directory, "resume", ["--release-dir", temporary])
            with self.assertRaises(cli.StateError):
                self.invoke(directory, "start", options)
            with patch.object(cli, "discover", return_value={**DISCOVERY, "aws_account_id": "999999999999"}), self.assertRaises(cli.StateError):
                self.invoke(directory, "resume", ["--release-dir", temporary])

    def test_running_stage_is_not_retried_or_completed(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(sys.modules, {"installer_bundle": types.SimpleNamespace(verify_release=lambda _: RELEASE)}), patch.object(cli, "discover", return_value=DISCOVERY):
            directory = Path(temporary) / "state"
            context = {**DISCOVERY, **RELEASE}
            store = cli.CheckpointStore(directory, context)
            with store.lock():
                store.resume()
                store.set_stage("infrastructure", "running")
            with self.assertRaises(cli.StateError):
                self.invoke(directory, "resume", ["--release-dir", temporary])
            with store.lock():
                self.assertEqual(store.resume()["stages"]["infrastructure"]["status"], "running")

    def test_invalid_release_never_queries_aws(self):
        def reject(_):
            raise ValueError("invalid release")
        with tempfile.TemporaryDirectory() as temporary, patch.dict(sys.modules, {"installer_bundle": types.SimpleNamespace(verify_release=reject)}), patch.object(cli, "discover") as discover:
            with self.assertRaises(ValueError):
                self.invoke(Path(temporary) / "state", "start", ["--release-dir", temporary])
            discover.assert_not_called()


if __name__ == "__main__":
    unittest.main()
