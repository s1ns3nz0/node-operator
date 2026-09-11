# Check objective: Verify context-bound infrastructure preparation without Terraform or cloud operations.
import importlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/release"))
infra = importlib.import_module("installer_infrastructure")
DISCOVERY = {"aws_profile": "operator", "aws_account_id": "123456789012", "aws_region": "ap-northeast-1",
             "deployment_name": "test-node", "availability_zones": ["ap-northeast-1a", "ap-northeast-1c"]}
ROLE = "arn:aws:iam::123456789012:role/backend"


@unittest.skipUnless(shutil.which("jq"), "release preparation requires jq")
class InfrastructurePreparationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name).resolve()
        self.bundle = self.directory / "bundle"
        script_dir = self.bundle / "source/scripts/release"
        script_dir.mkdir(parents=True)
        shutil.copyfile(ROOT / "scripts/release/prepare-zero-resource-inputs.sh", script_dir / "prepare-zero-resource-inputs.sh")
        self.destination = self.directory / "inputs"

    def tearDown(self):
        self.temporary.cleanup()

    def test_real_release_script_prepares_private_inputs_and_reuses_without_execution(self):
        result = infra.prepare_inputs(self.bundle, self.destination, DISCOVERY, ROLE)
        self.assertEqual(result, self.destination / "zero-resource-inputs.json")
        for name, expected in infra.expected_inputs(self.destination, DISCOVERY, ROLE).items():
            path = self.destination / name
            self.assertEqual(json.loads(path.read_text()), expected)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        with patch.object(infra.subprocess, "run") as run:
            self.assertEqual(infra.prepare_inputs(self.bundle, self.destination, DISCOVERY, ROLE), result)
        run.assert_not_called()
        self.assertEqual(list(self.directory.glob(".infrastructure-inputs-*")), [])

    def test_wrong_account_role_rejected_before_any_command(self):
        with patch.object(infra.subprocess, "run") as run, self.assertRaises(infra.InfrastructureError):
            infra.prepare_inputs(self.bundle, self.destination, DISCOVERY, ROLE.replace("123456789012", "999999999999"))
        run.assert_not_called()
        self.assertFalse(self.destination.exists())

    def test_changed_context_does_not_overwrite_existing_inputs(self):
        infra.prepare_inputs(self.bundle, self.destination, DISCOVERY, ROLE)
        original = (self.destination / "bootstrap-state.tfvars.json").read_bytes()
        with patch.object(infra.subprocess, "run") as run, self.assertRaises(infra.InfrastructureError):
            infra.prepare_inputs(self.bundle, self.destination, DISCOVERY, ROLE + "-other")
        run.assert_not_called()
        self.assertEqual((self.destination / "bootstrap-state.tfvars.json").read_bytes(), original)

    def test_failed_command_is_sanitized_and_staging_is_removed(self):
        failed = subprocess.CompletedProcess([], 1, "secret stdout", "secret stderr")
        with patch.object(infra.subprocess, "run", return_value=failed), self.assertRaises(infra.InfrastructureError) as error:
            infra.prepare_inputs(self.bundle, self.destination, DISCOVERY, ROLE)
        self.assertNotIn("secret", str(error.exception))
        self.assertFalse(self.destination.exists())
        self.assertEqual(list(self.directory.glob(".infrastructure-inputs-*")), [])

    def test_corrupt_or_extra_input_is_not_accepted(self):
        infra.prepare_inputs(self.bundle, self.destination, DISCOVERY, ROLE)
        path = self.destination / "baseline.tfvars.json"
        path.write_text('{"enable_vault_bootstrap_cluster_admin":true}')
        with self.assertRaises(infra.InfrastructureError):
            infra.prepare_inputs(self.bundle, self.destination, DISCOVERY, ROLE)

    def test_environment_keeps_github_and_binds_selected_aws_profile(self):
        original_run = subprocess.run
        with patch.dict(os.environ, {"GITHUB_TOKEN": "sentinel", "AWS_SECRET_ACCESS_KEY": "private"}), patch.object(infra.subprocess, "run", wraps=original_run) as run:
            infra.prepare_inputs(self.bundle, self.destination, DISCOVERY, ROLE)
            environment = run.call_args.kwargs["env"]
            self.assertEqual(environment["GITHUB_TOKEN"], "sentinel")
            self.assertNotIn("AWS_SECRET_ACCESS_KEY", environment)
            self.assertEqual(environment["AWS_PROFILE"], "operator")
            self.assertEqual(os.environ["AWS_SECRET_ACCESS_KEY"], "private")

    def test_destination_created_at_publish_is_preserved(self):
        original = infra.publish_directory
        observed = {}
        def race(source, destination):
            destination.mkdir(mode=0o700)
            observed["inode"] = destination.stat().st_ino
            return original(source, destination)
        with patch.object(infra, "publish_directory", side_effect=race), self.assertRaises(infra.InfrastructureError):
            infra.prepare_inputs(self.bundle, self.destination, DISCOVERY, ROLE)
        self.assertEqual(self.destination.stat().st_ino, observed["inode"])
        self.assertEqual(list(self.destination.iterdir()), [])
        self.assertEqual(list(self.directory.glob(".infrastructure-inputs-*")), [])


if __name__ == "__main__":
    unittest.main()
