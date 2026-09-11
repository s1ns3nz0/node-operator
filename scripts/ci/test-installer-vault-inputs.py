# Check objective: Exercise local Vault bootstrap input binding and fail-closed artifact scope checks.
from __future__ import annotations
import json, os, sys, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; sys.path.insert(0,str(ROOT/"scripts/release")); import installer_vault_inputs as vault; import installer_infrastructure as infrastructure
D={"aws_profile":"operator","aws_account_id":"123456789012","aws_region":"ap-northeast-1","deployment_name":"test-node","availability_zones":["ap-northeast-1a","ap-northeast-1c"]}
class Tests(unittest.TestCase):
 def setUp(self):
  self.t=tempfile.TemporaryDirectory(); self.root=Path(self.t.name); os.chmod(self.root,0o700); self.state=self.root/"state"; self.state.mkdir(mode=0o700); (self.state/"terraform-work").mkdir(mode=0o700)
  self.repo="123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/node-operator-baseline-gitops-vault"; self.image=self.repo+"@sha256:"+"a"*64
  baseline={"deployment_account_id":{"value":"123456789012"},"cluster_name":{"value":"test-node"},"vault_unseal_key_arn":{"value":"arn:aws:kms:ap-northeast-1:123456789012:key/abcd"},"vault_role_arn":{"value":"arn:aws:iam::123456789012:role/vault"},"private_subnet_ids":{"value":["subnet-abc"]},"private_gitops_ecr_repository_urls":{"value":{"vault":self.repo,"vault_chart":self.repo+"/vault"}}}; [item.update(sensitive=False) for item in baseline.values()]; self.write(self.state/"terraform-work/baseline-output.json",baseline)
  inputs=self.state/"infrastructure-inputs"; inputs.mkdir(mode=0o700); values=infrastructure.expected_inputs(inputs,D,"arn:aws:iam::123456789012:role/NodeOperatorTerraformApply"); [self.write(inputs/name,value) for name,value in values.items()]
  self.art=self.root/"artifacts.json"; self.write(self.art,{"schema_version":1,"aws_account_id":D["aws_account_id"],"aws_region":D["aws_region"],"deployment_name":D["deployment_name"],"images":{"bootstrap":self.image,"server":self.image,"agent":self.image,"injector":self.image,"audit_relay":self.image},"chart":{"version":"0.31.0","digest":"sha256:"+"b"*64}})
 def tearDown(self): self.t.cleanup()
 def write(self,p,v): p.parent.mkdir(parents=True,exist_ok=True); p.write_text(json.dumps(v)); os.chmod(p,0o600)
 def test_valid_idempotent(self):
  result=vault.prepare_vault_inputs(self.state,D,self.art); self.assertEqual(result.stat().st_mode&0o777,0o600); self.assertEqual(json.loads(result.read_text())["vault_runtime_images"], {key:self.image for key in ("server","agent","injector","audit_relay")}); self.assertTrue(vault.prepare_vault_inputs(self.state,D,self.art).exists())
 def test_foreign_and_unexpected_rejected(self):
  data=json.loads(self.art.read_text()); data["images"]["server"]="999999999999.dkr.ecr.ap-northeast-1.amazonaws.com/x@sha256:"+"a"*64; self.write(self.art,data)
  with self.assertRaises(vault.VaultInputsError): vault.prepare_vault_inputs(self.state,D,self.art)
  self.assertFalse((self.state/"vault-bootstrap-inputs").exists())
 def test_existing_destination_is_not_overwritten(self):
  result=vault.prepare_vault_inputs(self.state,D,self.art); result.write_text("changed")
  with self.assertRaises(vault.VaultInputsError): vault.prepare_vault_inputs(self.state,D,self.art)
 def test_original_baseline_config_is_required_and_bound(self):
  path=self.state/"infrastructure-inputs/baseline.tfvars.json"; original=path.read_bytes(); path.unlink()
  with self.assertRaises(vault.VaultInputsError): vault.prepare_vault_inputs(self.state,D,self.art)
  data=json.loads(original); data["enable_vault_bootstrap_cluster_admin"]=True; self.write(path,data)
  with self.assertRaises(vault.VaultInputsError): vault.prepare_vault_inputs(self.state,D,self.art)
  self.assertFalse((self.state/"vault-bootstrap-inputs").exists())
 def test_sensitive_missing_and_foreign_baseline_values_are_rejected(self):
  path=self.state/"terraform-work/baseline-output.json"; original=json.loads(path.read_text())
  for name,field,value in (("vault_unseal_key_arn","sensitive",True),("vault_role_arn","value","arn:aws:iam::999999999999:role/vault"),("private_gitops_ecr_repository_urls","value",{"vault":self.repo,"vault_chart":self.repo+";unsafe"}),("private_subnet_ids","value",[])):
   with self.subTest(name=name):
    data=json.loads(json.dumps(original)); data[name][field]=value; self.write(path,data)
    with self.assertRaises(vault.VaultInputsError): vault.prepare_vault_inputs(self.state,D,self.art)
    self.assertFalse((self.state/"vault-bootstrap-inputs").exists())
  data=json.loads(json.dumps(original)); del data["vault_role_arn"]; self.write(path,data)
  with self.assertRaises(vault.VaultInputsError): vault.prepare_vault_inputs(self.state,D,self.art)
 def test_artifact_symlink_and_unexpected_keys_are_rejected(self):
  original=json.loads(self.art.read_text()); original["unexpected"]="ignored?"; self.write(self.art,original)
  with self.assertRaises(vault.VaultInputsError): vault.prepare_vault_inputs(self.state,D,self.art)
  target=self.root/"target.json"; self.art.rename(target); self.art.symlink_to(target)
  with self.assertRaises(vault.VaultInputsError): vault.prepare_vault_inputs(self.state,D,self.art)
 def test_semantically_identical_artifact_and_changed_input(self):
  result=vault.prepare_vault_inputs(self.state,D,self.art); before=result.read_bytes()
  value=json.loads(self.art.read_text()); self.art.write_text(json.dumps(value,indent=2))
  self.assertEqual(vault.prepare_vault_inputs(self.state,D,self.art).read_bytes(),before)
  value["images"]["server"]=self.repo+"@sha256:"+"c"*64; self.write(self.art,value)
  with self.assertRaises(vault.VaultInputsError): vault.prepare_vault_inputs(self.state,D,self.art)
  self.assertEqual(result.read_bytes(),before)
if __name__=="__main__": unittest.main()
