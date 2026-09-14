# Check objective: the shell-facing Vault pre-EKS adapter binds only explicit, validated inputs.
import contextlib, importlib.util, io, json, os, subprocess, sys, tempfile, types, unittest
from pathlib import Path
from unittest.mock import Mock, patch

ROOT=Path(__file__).resolve().parents[2]
RELEASE=ROOT/"scripts/release"
CLI=RELEASE/"mirror-installer-vault-artifacts.py"
sys.path.insert(0,str(RELEASE))
from installer_artifact_prerequisites import projection, _projection_fingerprint

mirror_spec=importlib.util.spec_from_file_location("mirror_fixture",Path(__file__).with_name("test-installer-artifact-mirror.py"))
mirror_fixture=importlib.util.module_from_spec(mirror_spec); mirror_spec.loader.exec_module(mirror_fixture)
adapter_spec=importlib.util.spec_from_file_location("vault_adapter",CLI)
adapter=importlib.util.module_from_spec(adapter_spec); adapter_spec.loader.exec_module(adapter)


class VaultMirrorCLI(unittest.TestCase):
 def fixture(self, root):
  state=root/"state"; work=state/"terraform-work"; bundle=root/"bundle"; inputs=root/"inputs/zero-resource"; fake=root/"fake-bin"
  work.mkdir(parents=True); (bundle/"rendered").mkdir(parents=True); inputs.mkdir(parents=True); fake.mkdir()
  for directory in (state,work,bundle,inputs): os.chmod(directory,0o700)
  account="123456789012"; region="ap-northeast-2"; name="node-operator"; revision="c"*40
  for filename,value in (("bootstrap-state.tfvars.json",{"aws_account_id":account}),("foundation-network.tfvars.json",{"aws_region":region}),("baseline.tfvars.json",{"name":name})):
   path=inputs/filename; path.write_text(json.dumps(value)); os.chmod(path,0o600)
  manifest=bundle/"bundle-manifest.json"; manifest.write_text("{}"); os.chmod(manifest,0o600)
  fingerprint=_projection_fingerprint(inputs,bundle); checkpoint=work/"zero-inputs.sha256"; checkpoint.write_text(fingerprint); os.chmod(checkpoint,0o600)
  receipt=projection(mirror_fixture._fixture.state_fixture(),account,region,name,fingerprint)
  projected=work/"artifact-prerequisites.json"; projected.write_text(json.dumps(receipt)); os.chmod(projected,0o600)
  index=bundle/"rendered/installer-artifact-index.json"; index.write_text(json.dumps(mirror_fixture.strict_index(revision))); os.chmod(index,0o600)
  aws=fake/"aws"; aws.write_text("""#!/usr/bin/env python3
import json, os, sys
a=sys.argv[1:]; account=os.environ['FAKE_ACCOUNT']
if a[:2] == ['sts','get-caller-identity']: print(account)
elif a[:2] == ['ecr','get-login-password']: print('token')
elif a[:2] == ['ecr','describe-images']:
 def value(flag): return a[a.index(flag)+1]
 tag=value('--image-ids').split('imageTag=',1)[1]
 state_file=os.environ['FAKE_ECR_STATE']; state=json.load(open(state_file)) if os.path.exists(state_file) else {}
 key=value('--repository-name')+'|'+tag
 if not state.get(key):
  state['_pending']=key; json.dump(state,open(state_file,'w')); print('ImageNotFoundException',file=sys.stderr); raise SystemExit(255)
 print(json.dumps({'imageDetails':[{'registryId':value('--registry-id'),'repositoryName':value('--repository-name'),'imageDigest':os.environ['FAKE_DIGEST'],'imageTags':[tag]}]}))
else: raise SystemExit(64)
"""); os.chmod(aws,0o700)
  docker=fake/"docker"; docker.write_text("""#!/usr/bin/env python3
import json, os, sys
a=sys.argv[1:]
with open(os.environ['FAKE_LOG'],'a') as out: out.write(' '.join(a)+'\\n')
if a[:2] == ['run','--rm']:
 state_file=os.environ['FAKE_ECR_STATE']; state=json.load(open(state_file)) if os.path.exists(state_file) else {}
 state['_runs']=state.get('_runs',0)+1
 if str(state['_runs']) == os.environ.get('FAKE_FAIL_COPY_AT',''):
  json.dump(state,open(state_file,'w')); raise SystemExit(23)
 pending=state.pop('_pending',None)
 if pending: state[pending]=True
 json.dump(state,open(state_file,'w'))
"""); os.chmod(docker,0o700)
  env={**os.environ,"PATH":str(fake)+os.pathsep+os.environ["PATH"],"FAKE_ACCOUNT":account,"FAKE_LOG":str(root/"docker.log"),"FAKE_ECR_STATE":str(root/"ecr.json"),"FAKE_DIGEST":"sha256:"+"a"*64}
  args=["--bundle-root",str(bundle),"--state-dir",str(state),"--work-dir",str(work),"--inputs-dir",str(inputs),"--account",account,"--region",region,"--deployment-name",name,"--profile","offline","--release-sha",revision]
  return state,bundle,env,args
 def command(self, action, args, env):
  return subprocess.run([sys.executable,str(CLI),action,*args],text=True,capture_output=True,env=env,check=False)
 def test_mirror_and_verify_use_actual_projection_with_fake_external_commands(self):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp).resolve(); state,_,env,args=self.fixture(root)
   mirrored=self.command("mirror",args,env); self.assertEqual(mirrored.returncode,0,mirrored.stderr); self.assertIn("Vault subset",mirrored.stdout)
   self.assertTrue((state/"vault-artifact-manifest.json").is_file()); self.assertTrue((state/"vault-artifact-mirror-receipt.json").is_file()); self.assertTrue((state/"vault-pre-eks-artifact-mirror-binding.json").is_file())
   verified=self.command("verify",args,env); self.assertEqual(verified.returncode,0,verified.stderr); self.assertIn("Vault subset",verified.stdout)
   # Components sharing a repository/tag/digest need no duplicate copy.
   self.assertGreaterEqual((root/"docker.log").read_text().count("run --rm"),5)
 def test_wrong_identity_stops_before_docker_and_relative_path_stops_before_aws(self):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp).resolve(); _,bundle,env,args=self.fixture(root); env["FAKE_ACCOUNT"]="210987654321"
   failed=self.command("mirror",args,env); self.assertEqual(failed.returncode,2); self.assertIn("operation failed",failed.stderr); self.assertFalse((root/"docker.log").exists())
   relative=list(args); relative[relative.index("--bundle-root")+1]=str(bundle.relative_to(root))
   failed=self.command("mirror",relative,{**env,"FAKE_ACCOUNT":"123456789012"}); self.assertEqual(failed.returncode,2); self.assertIn("operation failed",failed.stderr); self.assertFalse((root/"docker.log").exists())
 def test_vault_resume_recovers_partial_copy_with_persistent_tag_only_ecr_state(self):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp).resolve(); state,_,env,args=self.fixture(root)
   failed=self.command("mirror",args,{**env,"FAKE_FAIL_COPY_AT":"2"})
   self.assertEqual(failed.returncode,2); marker=state/"vault-pre-eks-artifact-mirror-uncertain.json"; self.assertTrue(marker.exists())
   first=(root/"docker.log").read_text(); resumed=self.command("resume",args,env)
   self.assertEqual(resumed.returncode,0,resumed.stderr); self.assertIn("Vault subset",resumed.stdout)
   self.assertTrue((state/"vault-artifact-mirror-receipt.json").exists()); self.assertFalse(marker.exists())
   self.assertGreater((root/"docker.log").read_text().count("run --rm"),first.count("run --rm"))
 def test_non_vault_scope_dispatches_to_fake_full_helper_with_explicit_resume_only(self):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp).resolve(); state,bundle,_,args=self.fixture(root); work=state/"terraform-work"; inputs=root/"inputs/zero-resource"
   mirrored=Mock(); verified=Mock()
   fake=types.SimpleNamespace(mirror=mirrored,verify=verified)
   with patch.dict(sys.modules,{"installer_full_artifact_mirror":fake}),contextlib.redirect_stdout(io.StringIO()) as output:
    self.assertEqual(adapter.main(["mirror","--scope","non-vault",*args]),0)
    self.assertEqual(adapter.main(["resume","--scope","non-vault",*args]),0)
    self.assertEqual(adapter.main(["verify","--scope","non-vault",*args]),0)
   self.assertIn("Non-Vault subset",output.getvalue())
   self.assertEqual(mirrored.call_count,2)
   self.assertEqual(mirrored.call_args_list[0].args,(state,bundle,{"aws_account_id":"123456789012","aws_region":"ap-northeast-2","deployment_name":"node-operator"},"offline","c"*40))
   self.assertEqual(mirrored.call_args_list[0].kwargs,{"work_dir":work,"inputs_dir":inputs,"resume":False})
   self.assertEqual(mirrored.call_args_list[1].kwargs,{"work_dir":work,"inputs_dir":inputs,"resume":True})
   self.assertEqual(verified.call_args.args,(state,bundle,{"aws_account_id":"123456789012","aws_region":"ap-northeast-2","deployment_name":"node-operator"},"offline","c"*40))
   self.assertEqual(verified.call_args.kwargs,{"work_dir":work,"inputs_dir":inputs})
 def test_vault_scope_forwards_resume_only_when_requested(self):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp).resolve(); state,bundle,_,args=self.fixture(root); work=state/"terraform-work"; inputs=root/"inputs/zero-resource"; mirrored=Mock()
   with patch.object(adapter,"mirror",mirrored),contextlib.redirect_stdout(io.StringIO()) as output:
    self.assertEqual(adapter.main(["mirror",*args]),0)
    self.assertEqual(adapter.main(["resume",*args]),0)
   self.assertIn("Vault subset",output.getvalue()); self.assertEqual(mirrored.call_count,2)
   self.assertEqual(mirrored.call_args_list[0].args,(state,bundle,{"aws_account_id":"123456789012","aws_region":"ap-northeast-2","deployment_name":"node-operator"},"offline","c"*40))
   self.assertEqual(mirrored.call_args_list[0].kwargs,{"prerequisites_path":work/"artifact-prerequisites.json","inputs_dir":inputs,"work_dir":work})
   self.assertEqual(mirrored.call_args_list[1].kwargs,{"prerequisites_path":work/"artifact-prerequisites.json","inputs_dir":inputs,"work_dir":work,"resume":True})
 def test_invalid_scope_rejects_before_external_calls(self):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp).resolve(); _,_,env,args=self.fixture(root)
   invalid=self.command("mirror",["--scope","invalid",*args],env)
   self.assertEqual(invalid.returncode,2); self.assertIn("invalid choice",invalid.stderr); self.assertFalse((root/"docker.log").exists())


if __name__ == "__main__": unittest.main()
