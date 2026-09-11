#!/usr/bin/env python3
# Check objective: Platform starts only from reconciled authority and immutable state.
import json,os,sys,tempfile,unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/"scripts/release"));import installer_vault_platform as p
D={"aws_account_id":"123456789012","aws_region":"ap-northeast-1","deployment_name":"node"};I="123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/vault@sha256:"+"a"*64
class T(unittest.TestCase):
 def setUp(self):
  self.t=tempfile.TemporaryDirectory();self.s=Path(self.t.name)/"s";self.s.mkdir(mode=0o700);self.bundle=Path(self.t.name)/"bundle";self.bundle.mkdir();(self.s/"terraform-work").mkdir(mode=0o700)
  bs="v";contract={"name":"p","arn":"arn:aws:codebuild:ap-northeast-1:123456789012:project/p","service_role_arn":"role","image":I,"source_type":"NO_SOURCE","buildspec_sha256":__import__("hashlib").sha256(bs.encode()).hexdigest(),"aws_account_id":D["aws_account_id"],"aws_region":D["aws_region"]};self.w(self.s/"terraform-work/baseline-output.json",{});self.refreshed={"private_gitops_ecr_repository_urls":{"value":{"vault":"123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/vault"},"sensitive":False},"vault_bootstrap_project_contract":{"value":contract,"sensitive":False}};self.plan=self.s/"vault-authority-plans/grant/receipt.json";self.plan.parent.mkdir(parents=True);self.ok=self.s/"vault-authority-plans/grant-success.json";self.w(self.plan,{"schema_version":1,"phase":"grant","plan_sha256":"b"*64,**D,"scope":{},"applied":False});self.w(self.ok,{"schema_version":1,"phase":"grant","plan_sha256":"b"*64,"applied":True});self.idx=self.bundle/"rendered/installer-artifact-index.json";self.idx.parent.mkdir();self.mirror=self.s/"vault-artifact-mirror-receipt.json";components={name:{} for name in p.NAMES};components["vault-bootstrap"]={"image_ref":"ghcr.io/source@sha256:"+"a"*64,"manifest_digest":"sha256:"+"a"*64};self.w(self.idx,{"schema_version":1,"release_revision":"c"*40,"components":components});self.w(self.mirror,{**D,"status":"verified","release_revision":"c"*40,"index_sha256":p.digest(self.idx),"artifacts":{"vault-bootstrap":{"image_ref":I,"manifest_digest":"sha256:"+"a"*64}}})
 def tearDown(self):self.t.cleanup()
 def w(self,x,v):x.write_text(json.dumps(v));os.chmod(x,0o600)
 def responses(self,status="SUCCEEDED",bid="p:1"):
  proj={"projects":[{"name":"p","arn":"arn:aws:codebuild:ap-northeast-1:123456789012:project/p","serviceRole":"role","source":{"type":"NO_SOURCE","buildspec":"v"},"environment":{"image":I,"imagePullCredentialsType":"SERVICE_ROLE","privilegedMode":False}}]};return [{"Account":D["aws_account_id"]},proj,{"build":{"id":bid}},{"builds":[{"id":bid,"projectName":"p","buildComplete":True,"buildStatus":status}]}]
 def call(self,r):
  calls=[]
  with patch.object(p,"reconcile_vault_authority",return_value=self.refreshed) as rec,patch.object(p.subprocess,"run",side_effect=lambda a,**k:(calls.append(a) or SimpleNamespace(stdout=json.dumps(r.pop(0))))):out=p.run(self.bundle,self.s,D,"profile")
  return out,calls,rec
 def test_success_exact_and_no_override(self):
  out,calls,rec=self.call(self.responses());self.assertEqual(out["status"],"succeeded");self.assertRegex(out["project_contract_sha256"],r"^[0-9a-f]{64}$");rec.assert_called_once();self.assertNotIn("--buildspec-override"," ".join(sum(calls,[])))
 def test_foreign_grant_identity_project_and_wrong_build_stop(self):
  self.w(self.ok,{"status":"succeeded"});
  with self.assertRaises(p.PlatformError):self.call(self.responses())
  self.w(self.ok,{"schema_version":1,"phase":"grant","plan_sha256":"b"*64,"applied":True});r=self.responses();r[0]={"Account":"0"}
  with self.assertRaises(p.PlatformError):self.call(r)
  r=self.responses();r[1]["projects"][0]["environment"]["image"]="bad"
  with self.assertRaises(p.PlatformError):self.call(r)
  r=self.responses();r[1]["projects"][0]["source"]["buildspec"]="tampered"
  with self.assertRaises(p.PlatformError):self.call(r)
  r=self.responses();r[3]["builds"][0]["id"]="other"
  with self.assertRaises(p.PlatformError):self.call(r)
 def test_timeout_resume_and_no_restart(self):
  with self.assertRaises(p.PlatformError):self.call(self.responses("IN_PROGRESS"))
  r=self.responses();r.pop(2);r[2]={"builds":[{"id":"p:1","projectName":"p","buildComplete":True,"buildStatus":"SUCCEEDED"}]}
  out,calls,_=self.call(r);self.assertEqual(out["status"],"succeeded");self.assertFalse(any("start-build" in c for c in calls))
 def test_intent_without_id_never_starts(self):
  contract=self.refreshed["vault_bootstrap_project_contract"]["value"];bind={"schema_version":1,**D,"grant_plan_sha256":"b"*64,"artifact_index_sha256":p.digest(self.idx),"project_contract_sha256":__import__("hashlib").sha256(json.dumps(contract,sort_keys=True,separators=(",",":")).encode()).hexdigest(),"project":"p","image_ref":I};self.w(self.s/"vault-platform-intent.json",bind)
  with self.assertRaises(p.PlatformError):self.call(self.responses())
if __name__=="__main__":unittest.main()
