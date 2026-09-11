"""Check read-only AWS discovery, identity binding and sanitized failures."""
import importlib.util
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("preflight", Path(__file__).resolve().parents[1] / "release/installer_preflight.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PreflightTests(unittest.TestCase):
    def test_discovery_does_not_claim_apply_permission(self):
        responses = [{"Account": "123456789012", "Arn": "arn:aws:sts::123456789012:assumed-role/operator/session"},
                     {"AvailabilityZones": [{"ZoneName": "ap-northeast-1c", "State": "available"}, {"ZoneName": "ap-northeast-1a", "State": "available"}]},
                     {"clusters": ["test-node"]}]
        with patch.object(module, "aws_read", side_effect=responses) as read:
            result = module.discover("test", "ap-northeast-1", "test-node")
        self.assertEqual(result["availability_zones"], ["ap-northeast-1a", "ap-northeast-1c"])
        self.assertTrue(result["cluster_name_present"])
        self.assertEqual(result["provisioning_permissions"], "not_verified")
        self.assertEqual([c.args[2][0] for c in read.call_args_list], ["sts", "ec2", "eks"])

    def test_invalid_inputs_never_call_aws(self):
        for profile, region, name in [("bad profile", "ap-northeast-1", "test"), ("ok", "us-east-1", "test"), ("ok", "ap-northeast-1", "../bad")]:
            with patch.object(module, "aws_read") as read, self.assertRaises(module.PreflightError):
                module.discover(profile, region, name)
            read.assert_not_called()

    def test_wrong_account_and_root_rejected(self):
        for arn in ["arn:aws:iam::999999999999:role/operator", "arn:aws:iam::123456789012:root"]:
            with patch.object(module, "aws_read", return_value={"Account": "123456789012", "Arn": arn}), self.assertRaises(module.PreflightError):
                module.discover("test", "ap-northeast-1", "test-node")

    def test_profile_is_explicit_and_errors_do_not_leak(self):
        with patch.dict(os.environ, {"GITHUB_TOKEN": "sentinel", "AWS_SECRET_ACCESS_KEY": "private"}), patch.object(module.shutil, "which", return_value="aws"), patch.object(module.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "secret", "private")) as run:
            with self.assertRaises(module.PreflightError) as error:
                module.aws_read("test", "ap-northeast-1", ["sts", "get-caller-identity"])
            self.assertNotIn("secret", str(error.exception))
            self.assertNotIn("private", str(error.exception))
            self.assertEqual(run.call_args.kwargs["env"]["GITHUB_TOKEN"], "sentinel")
            self.assertNotIn("AWS_SECRET_ACCESS_KEY", run.call_args.kwargs["env"])
            self.assertEqual(os.environ["AWS_SECRET_ACCESS_KEY"], "private")
            self.assertEqual(run.call_args.args[0][1:5], ["--profile", "test", "--region", "ap-northeast-1"])


if __name__ == "__main__":
    unittest.main()
