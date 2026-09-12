# Check objective: Reject unsafe installer artifact mirror inputs before any registry copy.
import json, tempfile, unittest
from pathlib import Path
import sys
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"release"))
from installer_artifact_mirror import MirrorError, mirror, NAMES
class Mirror(unittest.TestCase):
 def fixture(self, root):
  bundle=root/"bundle"; (bundle/"rendered").mkdir(parents=True)
  digest="sha256:"+"a"*64; image=lambda n:{"image_ref":f"ghcr.io/s1ns3nz0/node-operator/{n}@{digest}","manifest_digest":digest}
  components={n:image(n) for n in NAMES if n not in {"vault-chart","cert-manager-chart"}}
  for n in ("vault-chart","cert-manager-chart"): components[n]={"approved_url":"https://vendor.invalid/"+n+".tgz","archive_sha256":"b"*64,"expected_oci_manifest_digest":digest,"tag":"v1","version":"1.2.3"}
  (bundle/"rendered/installer-artifact-index.json").write_text(json.dumps({"schema_version":1,"release_revision":"c"*40,"components":components}))
  state=root/"state"; state.mkdir(mode=0o700); (state/"terraform-work").mkdir()
  repos={k:"123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/private/"+v for k,v in {"vault":"vault","vault_chart":"vault/vault","cert_manager":"cert","cert_manager_chart":"cert/cert-manager"}.items()}
  out={"private_gitops_ecr_repository_urls":{"sensitive":False,"value":repos},"vault_audit_relay_ecr_repository_url":{"sensitive":False,"value":"123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/private/relay"}}
  (state/"terraform-work/baseline-output.json").write_text(json.dumps(out)); return state,bundle,digest
 def test_missing_or_wrong_index_never_starts_copy(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); state=root/"state"; state.mkdir(mode=0o700); (state/"terraform-work").mkdir()
   with self.assertRaises(MirrorError): mirror(state, root, {"aws_account_id":"123456789012","aws_region":"ap-northeast-1"}, "test", "a"*40)
 def test_uncertain_marker_blocks_retry(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); state=root/"state"; state.mkdir(mode=0o700); (state/"vault-artifact-mirror-uncertain.json").write_text("{}")
   with self.assertRaises(MirrorError): mirror(state, root, {"aws_account_id":"123456789012","aws_region":"ap-northeast-1"}, "test", "a"*40)
 def test_full_payload_flow_and_partial_failure_retains_marker(self):
  for partial in (False,True):
   with self.subTest(partial=partial), tempfile.TemporaryDirectory() as t:
    state,bundle,digest=self.fixture(Path(t))
    calls=[]
    class R:
     def __init__(self,s=""): self.stdout=s
    def run(args,**kwargs):
     calls.append((args,kwargs))
     if args[:3]==["aws","sts","get-caller-identity"]: return R("123456789012\n")
     if args[:3]==["aws","ecr","get-login-password"]: return R("token")
     if args[:3]==["aws","ecr","describe-images"]: return R(("sha256:"+"b"*64 if partial and len([x for x,_ in calls if x[:3]==["aws","ecr","describe-images"]])==1 else digest)+"\n")
     return R()
    discovery={"aws_account_id":"123456789012","aws_region":"ap-northeast-1","deployment_name":"node"}
    with patch("installer_artifact_mirror.subprocess.run",side_effect=run):
     if partial:
      with self.assertRaises(MirrorError): mirror(state,bundle,discovery,"profile","c"*40)
      self.assertTrue((state/"vault-artifact-mirror-uncertain.json").exists()); self.assertFalse((state/"vault-artifact-manifest.json").exists())
      with self.assertRaises(MirrorError): mirror(state,bundle,discovery,"profile","c"*40)
     else:
      output=mirror(state,bundle,discovery,"profile","c"*40); self.assertTrue(output.exists()); self.assertTrue((state/"vault-artifact-mirror-receipt.json").exists())
      manifest=json.loads(output.read_text()); self.assertEqual(set(manifest),{"schema_version","aws_account_id","aws_region","deployment_name","images","chart"}); self.assertEqual(set(manifest["images"]),{"bootstrap","server","agent","injector","audit_relay"}); self.assertEqual(manifest["images"]["server"],manifest["images"]["agent"])
      copies=[x for x,_ in calls if x[:3]==["docker","run","--rm"]]; self.assertEqual(len(copies),10)
      charts=[x for x in copies if "--entrypoint" in x]; self.assertEqual(len(charts),2)
      images=[x for x in copies if "--entrypoint" not in x]; self.assertEqual(len(images),8)
      self.assertTrue(all(any(part.startswith("docker://123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/private/") for part in call) for call in images))
      self.assertEqual({call[-1] for call in charts},{"oci://123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/private/vault","oci://123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/private/cert"})
      self.assertTrue(all("HELM_REGISTRY_CONFIG=/auth/config.json" in call for call in charts))
      described=[x for x,_ in calls if x[:3]==["aws","ecr","describe-images"]]; self.assertEqual(len(described),10)
      self.assertIn("private/vault/vault", described[8])
      self.assertIn("private/cert/cert-manager", described[9])
 def test_preflight_failure_has_no_marker_or_copy(self):
  with tempfile.TemporaryDirectory() as t:
   state,bundle,_=self.fixture(Path(t)); calls=[]
   def run(args,**kwargs):
    calls.append(args)
    if args[:2]==["docker","pull"]: raise __import__("subprocess").CalledProcessError(1,args)
    return type("R",(),{"stdout":"123456789012\n"})()
   with patch("installer_artifact_mirror.subprocess.run",side_effect=run), self.assertRaises(MirrorError):
    mirror(state,bundle,{"aws_account_id":"123456789012","aws_region":"ap-northeast-1","deployment_name":"node"},"profile","c"*40)
   self.assertFalse((state/"vault-artifact-mirror-uncertain.json").exists())
   self.assertFalse(any(call[:3]==["docker","run","--rm"] for call in calls))
if __name__=="__main__": unittest.main()

