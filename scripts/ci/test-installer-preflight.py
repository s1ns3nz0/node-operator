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
    def test_missing_tools_are_aggregated_without_executing_or_installing(self):
        with patch.object(module.shutil, "which", side_effect=lambda tool: "/bin/" + tool if tool in {"aws", "jq"} else None), patch.object(module.subprocess, "run") as run:
            result = module.local_prerequisites()
        run.assert_not_called()
        self.assertEqual(result["missing_by_stage"]["infrastructure"], ["terraform", "shasum", "rg"])
        self.assertIn("session-manager-plugin", result["missing_by_stage"]["ops_access"])
        self.assertIn("vault", result["missing_by_stage"]["vault"])
        self.assertEqual(result["versions"], "not_verified")

    def test_installed_tools_do_not_imply_runtime_readiness(self):
        with patch.object(module.shutil, "which", return_value="/bin/tool"):
            result = module.local_prerequisites()
        self.assertTrue(all(not missing for missing in result["missing_by_stage"].values()))
        self.assertEqual(result["runtime_health"], "not_verified")

    def test_discovery_does_not_claim_apply_permission(self):
        responses = [{"Account": "123456789012", "Arn": "arn:aws:sts::123456789012:assumed-role/operator/session"},
                     {"AvailabilityZones": [{"ZoneName": "ap-northeast-1c", "State": "available"}, {"ZoneName": "ap-northeast-1a", "State": "available"}]},
                     {"clusters": ["test-node"]}, [], [], ["test-node-foundation-flow-logs", "test-node-baseline-eks-cluster", "unrelated-role"],
                     {"Quota": {"QuotaCode": "L-0263D0A3", "ServiceCode": "ec2", "Value": 5}}, []]
        with patch.object(module, "aws_read", side_effect=responses) as read:
            result = module.discover("test", "ap-northeast-1", "test-node")
        self.assertEqual(result["availability_zones"], ["ap-northeast-1a", "ap-northeast-1c"])
        self.assertTrue(result["cluster_name_present"])
        self.assertEqual(result["provisioning_permissions"], "not_verified")
        self.assertEqual(result["iam_role_collisions"]["deployment_role_name_conflicts"], ["test-node-baseline-eks-cluster", "test-node-foundation-flow-logs"])
        self.assertEqual(result["iam_role_collisions"]["iam_permissions"], "not_verified")
        self.assertEqual([c.args[2][0] for c in read.call_args_list], ["sts", "ec2", "eks", "s3api", "dynamodb", "iam", "service-quotas", "ec2"])

    def test_elastic_ip_headroom_and_exhaustion_never_mutate(self):
        for allocated, expected in [(0, "sufficient_at_observation"), (4, "sufficient_at_observation"), (5, "requires_capacity_review")]:
            quota = {"Quota": {"QuotaCode": "L-0263D0A3", "ServiceCode": "ec2", "Value": 5.0}}
            with patch.object(module, "aws_read", side_effect=[quota, [f"eipalloc-{i:08x}" for i in range(allocated)]]) as read:
                result = module.elastic_ip_headroom("test", "ap-northeast-1")
            self.assertEqual(result["result"], expected)
            self.assertEqual(result["headroom_lower_bound"], 5 - allocated)
            self.assertFalse(result["reservation_created"])
            self.assertEqual([call.args[2][1] for call in read.call_args_list], ["get-service-quota", "describe-addresses"])

    def test_malformed_quota_or_inventory_is_not_capacity(self):
        for quota in ({}, {"Quota": []}, {"Quota": {"Value": 5}}, {"Quota": {"QuotaCode": "other", "ServiceCode": "ec2", "Value": 5}}):
            with patch.object(module, "aws_read", return_value=quota), self.assertRaises(module.PreflightError):
                module.elastic_ip_headroom("test", "ap-northeast-1")
        for value in (None, True, -1, 1.5, float("nan"), float("inf"), "5"):
            quota = {"Quota": {"QuotaCode": "L-0263D0A3", "ServiceCode": "ec2", "Value": value}}
            with patch.object(module, "aws_read", return_value=quota), self.assertRaises(module.PreflightError):
                module.elastic_ip_headroom("test", "ap-northeast-1")
        quota = {"Quota": {"QuotaCode": "L-0263D0A3", "ServiceCode": "ec2", "Value": 5}}
        for addresses in (None, {}, [None], ["eipalloc-1", "eipalloc-1"]):
            with patch.object(module, "aws_read", side_effect=[quota, addresses]), self.assertRaises(module.PreflightError):
                module.elastic_ip_headroom("test", "ap-northeast-1")

    def test_iam_role_collisions_keep_only_deployment_namespaces(self):
        roles = ["test-node-foundation-flow-logs", "test-node-baseline-vault", "test-node-baseline", "test-node-foundation-flow-logs-extra", "another-baseline-vault"]
        with patch.object(module, "aws_read", return_value=roles) as read:
            result = module.iam_role_collisions("test", "ap-northeast-1", "test-node")
        self.assertEqual(result["deployment_role_name_conflicts"], ["test-node-baseline-vault", "test-node-foundation-flow-logs"])
        self.assertEqual(result["checked_role_namespaces"], {"foundation_flow_logs": "test-node-foundation-flow-logs", "baseline_prefix": "test-node-baseline-"})
        self.assertEqual(result["role_policies"], "not_verified")
        self.assertEqual(read.call_args.args[2], ["iam", "list-roles", "--query", "Roles[].RoleName"])
        self.assertNotIn("--no-paginate", read.call_args.args[2])

    def test_invalid_iam_role_inventory_fails_closed_without_leaking_result(self):
        for response in [None, {}, "role", ["valid-role", 1], ["bad/role"]]:
            with patch.object(module, "aws_read", return_value=response), self.assertRaises(module.PreflightError) as error:
                module.iam_role_collisions("test", "ap-northeast-1", "test-node")
            self.assertEqual(str(error.exception), "AWS IAM role inventory is incomplete; no role name is considered available.")

    def test_backend_collision_does_not_authorize_adoption(self):
        bucket = "test-node-tfstate-123456789012-apnortheast1"
        with patch.object(module, "aws_read", side_effect=[[bucket], ["test-node-terraform-lock"]]):
            result = module.backend_collisions("test", "ap-northeast-1", "test-node", "123456789012")
        self.assertEqual(result["account_owned_bucket_conflicts"], [bucket])
        self.assertEqual(result["regional_table_conflicts"], ["test-node-terraform-lock"])
        self.assertEqual(result["existing_resource_adoption"], "not_authorized")
        self.assertEqual(result["global_bucket_availability"], "not_verified")

    def test_invalid_backend_inventory_is_not_treated_as_empty(self):
        for response in [None, {}, [123], ""]:
            with patch.object(module, "aws_read", side_effect=[response, []]), self.assertRaises(module.PreflightError):
                module.backend_collisions("test", "ap-northeast-1", "test-node", "123456789012")

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
