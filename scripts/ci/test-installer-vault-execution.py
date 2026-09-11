# Check objective: Ensure Vault plan staging never invokes the retained provider cache.
from __future__ import annotations
import os,sys,tempfile,unittest
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/"scripts/release"));import installer_vault_execution as v
class T(unittest.TestCase):
 def test_saved_plan_failures_preserve_original(self):
  for failure in ("init","drift","scope",None):
   with self.subTest(failure=failure):
    baseline=self.state/"terraform-work/baseline-output.json";baseline.write_text('{"fixture":true}');baseline.chmod(0o600)
    calls=[]
    def run(args,environment,output=False):
     calls.append(args)
     if "init" in args:return SimpleNamespace(returncode=1 if failure=="init" else 0)
     if "-detailed-exitcode" in args:return SimpleNamespace(returncode=2 if failure=="drift" else 0)
     if "output" in args:return SimpleNamespace(returncode=0,stdout=baseline.read_bytes())
     if "show" in args:return SimpleNamespace(returncode=0,stdout=json.dumps({"format_version":"1.2","terraform_version":"1.5.7","resource_changes":[{"address":"aws_eks_cluster.private" if failure=="scope" else "aws_codebuild_project.vault_bootstrap[0]","mode":"managed","change":{"actions":["create"]}}]}))
     Path(next(x[5:] for x in args if x.startswith("-out="))).write_bytes(b"plan");return SimpleNamespace(returncode=0)
    with patch.object(v,"validate_vault_workspace",return_value=self.orig),patch.object(v,"prepare_vault_inputs",return_value=self.state/"delta.json"),patch.object(v,"_identity"),patch.object(v,"_run",side_effect=run),patch.object(v.shutil,"disk_usage",return_value=SimpleNamespace(free=3*1024**3)):
     args=(self.bundle,self.state,{"aws_account_id":"123456789012","aws_region":"ap-northeast-1","deployment_name":"test"},"p",self.state/"artifacts")
     if failure:
      with self.assertRaises(v.VaultExecutionError):v.plan_vault_prepare(*args)
      self.assertFalse((self.state/"vault-plans/prepare").exists());self.assertFalse((self.state/"vault-bootstrap-plan-work").exists())
     else:self.assertEqual(len(v.plan_vault_prepare(*args)),64)
    self.assertTrue((self.orig/".terraform/terraform.tfstate").is_file())
    self.assertFalse(any(f"-chdir={self.orig}" in command for command in calls))
    self.assertFalse(any("apply" in command for command in calls))
 def setUp(self):
  self.t=tempfile.TemporaryDirectory();self.root=Path(self.t.name);os.chmod(self.root,0o700);self.state=self.root/"state";self.state.mkdir(mode=0o700);self.bundle=self.root/"bundle";src=self.bundle/"source/infra/terraform";src.mkdir(parents=True);(src/"main.tf").write_text("x");self.orig=self.state/"terraform-work/baseline";self.orig.mkdir(parents=True);os.chmod(self.state/"terraform-work",0o700);os.chmod(self.orig,0o700);(self.orig/"foundation-network.auto.tfvars.json").write_text("{}");(self.orig/".terraform").mkdir();(self.orig/".terraform/terraform.tfstate").write_text('{"backend":{"config":{"bucket":"b","key":"node-operator/baseline/terraform.tfstate","region":"ap-northeast-1","dynamodb_table":"t","kms_key_id":"k","encrypt":true}}}');os.chmod(self.orig/".terraform/terraform.tfstate",0o600)
 def tearDown(self):self.t.cleanup()
 def test_fresh_init_only(self):
  d={"aws_region":"ap-northeast-1","deployment_name":"x"};
  with patch.object(v,"validate_vault_workspace",return_value=self.orig),patch.object(v.shutil,"disk_usage",return_value=SimpleNamespace(free=3*1024**3)),patch.object(v.subprocess,"run",return_value=SimpleNamespace(returncode=0)) as run:
   out=v.prepare_vault_plan_workspace(self.bundle,self.state,d,"p")
  args=run.call_args[0][0];self.assertTrue(next(x for x in args if x.startswith("-chdir=")).split("=",1)[1].startswith(str(self.state/".vault-plan-")));self.assertIn("-lockfile=readonly",args);self.assertNotIn(str(self.orig)," ".join(args));self.assertFalse((out/".terraform/terraform.tfstate").exists())
if __name__=="__main__":unittest.main()
