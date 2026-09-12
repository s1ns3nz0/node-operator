"""Mirror the release-bound Vault prerequisites into existing private ECR repositories."""
from __future__ import annotations
import hashlib, json, os, re, stat, subprocess, tempfile, shutil
from pathlib import Path

SHA = re.compile(r"^[0-9a-f]{40}$"); DIGEST = re.compile(r"^sha256:[a-f0-9]{64}$")
class MirrorError(RuntimeError): pass
NAMES = {"vault-bootstrap","vault-audit-relay","gitops-oci-mirror","vault-server","vault-injector","cert-manager-controller","cert-manager-webhook","cert-manager-cainjector","cert-manager-startupapicheck","vault-chart","cert-manager-chart"}

def _read(path: Path):
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 4*1024*1024: raise MirrorError("artifact input is unsafe")
    try: return json.loads(path.read_text())
    except Exception as e: raise MirrorError("artifact input is invalid") from e

def _write(path: Path, value: dict):
    if not path.parent.is_dir() or stat.S_IMODE(path.parent.stat().st_mode) != 0o700 or path.exists() or path.is_symlink(): raise MirrorError("mirror output path is unsafe")
    fd, tmp = tempfile.mkstemp(prefix=".mirror-", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write((json.dumps(value, sort_keys=True)+"\n").encode())
            handle.flush(); os.fsync(handle.fileno())
        fd = -1
        os.link(tmp, path)
    except Exception as e: raise MirrorError("could not atomically publish mirror output") from e
    finally:
        if fd != -1:
            os.close(fd)
        try: os.unlink(tmp)
        except FileNotFoundError: pass

def mirror(state_dir: Path, bundle_root: Path, discovery: dict, profile: str, release_sha: str) -> Path:
    index_path = bundle_root / "rendered/installer-artifact-index.json"; index = _read(index_path)
    if not SHA.fullmatch(release_sha) or set(index) != {"schema_version","release_revision","components"} or index["schema_version"] != 1 or index["release_revision"] != release_sha or set(index["components"]) != NAMES: raise MirrorError("artifact index is not the exact selected release index")
    baseline = _read(state_dir / "terraform-work/baseline-output.json")
    def value(name):
        item=baseline.get(name)
        if not isinstance(item,dict) or item.get("sensitive") is not False: raise MirrorError("baseline output is unavailable")
        return item.get("value")
    repos=value("private_gitops_ecr_repository_urls"); relay=value("vault_audit_relay_ecr_repository_url")
    account, region = discovery["aws_account_id"], discovery["aws_region"]; prefix=f"{account}.dkr.ecr.{region}.amazonaws.com/"
    if not isinstance(repos,dict) or set(repos) < {"vault","vault_chart","cert_manager","cert_manager_chart"} or not isinstance(relay,str) or any(not isinstance(x,str) or not x.startswith(prefix) for x in [repos["vault"],repos["vault_chart"],repos["cert_manager"],repos["cert_manager_chart"],relay]): raise MirrorError("baseline does not bind all existing private destinations")
    marker=state_dir/"vault-artifact-mirror-uncertain.json"; manifest=state_dir/"vault-artifact-manifest.json"; receipt=state_dir/"vault-artifact-mirror-receipt.json"
    if marker.exists(): raise MirrorError("prior mirror outcome is uncertain; reconcile before retry")
    if manifest.exists() or receipt.exists(): raise MirrorError("mirror output already exists; reconcile instead of overwriting")
    image_names={"vault-bootstrap","vault-audit-relay","gitops-oci-mirror","vault-server","vault-injector","cert-manager-controller","cert-manager-webhook","cert-manager-cainjector","cert-manager-startupapicheck"}
    for component in image_names:
        item=index["components"][component]
        if not isinstance(item,dict) or not isinstance(item.get("image_ref"),str) or not DIGEST.fullmatch(item.get("manifest_digest","")) or not item["image_ref"].endswith("@"+item["manifest_digest"]):
            raise MirrorError("artifact index image component schema is invalid")
    for component in ("vault-chart","cert-manager-chart"):
        item=index["components"][component]
        if not isinstance(item,dict) or not isinstance(item.get("approved_url"),str) or not item["approved_url"].startswith("https://") or not re.fullmatch(r"[a-f0-9]{64}",item.get("archive_sha256","")) or not DIGEST.fullmatch(item.get("expected_oci_manifest_digest","")) or not re.fullmatch(r"[A-Za-z0-9._-]+",item.get("tag","")) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+",item.get("version","")):
            raise MirrorError("artifact index chart component schema is invalid")
    image_dest={"vault-bootstrap":repos["vault"],"vault-server":repos["vault"],"vault-injector":repos["vault"],"cert-manager-controller":repos["cert_manager"],"cert-manager-webhook":repos["cert_manager"],"cert-manager-cainjector":repos["cert_manager"],"cert-manager-startupapicheck":repos["cert_manager"],"vault-audit-relay":relay}
    image_plan={}
    for name,destination in image_dest.items():
        item=index["components"][name]; digest=item["manifest_digest"]; tag=item.get("tag",digest.removeprefix("sha256:"))
        if not isinstance(tag,str) or not re.fullmatch(r"[A-Za-z0-9._-]+",tag): raise MirrorError("image destination tag is invalid")
        image_plan[name]=(destination,tag)
    tool=index["components"]["gitops-oci-mirror"].get("image_ref",""); chart_tool=index["components"]["vault-bootstrap"].get("image_ref","")
    if not isinstance(tool,str) or not tool.startswith("ghcr.io/s1ns3nz0/node-operator/gitops-oci-mirror@sha256:") or not isinstance(chart_tool,str) or "@sha256:" not in chart_tool: raise MirrorError("pinned mirror tooling is invalid")
    env=dict(os.environ, AWS_PROFILE=profile, AWS_REGION=region)
    for image in (tool,chart_tool):
        subprocess.run(["docker","pull",image],check=True,capture_output=True,text=True,env=env)
    for command in (["docker","image","inspect",tool],["docker","image","inspect",chart_tool],["aws","sts","get-caller-identity","--query","Account","--output","text"]):
        result=subprocess.run(command,check=True,capture_output=True,text=True,env=env)
        if command[0] == "aws" and result.stdout.strip() != account: raise MirrorError("selected AWS profile is not the selected account")
    work=Path(tempfile.mkdtemp(prefix=".vault-artifact-mirror-",dir=state_dir)); os.chmod(work,0o700)
    auth=work/"auth"; auth.mkdir(mode=0o700)
    registry=f"{account}.dkr.ecr.{region}.amazonaws.com"
    try:
        password=subprocess.run(["aws","ecr","get-login-password","--region",region],check=True,capture_output=True,text=True,env=env).stdout
        subprocess.run(["docker","login","--username","AWS","--password-stdin",registry],check=True,input=password,text=True,env={**env,"DOCKER_CONFIG":str(auth)})
        # Every payload, destination and tool was checked before this point.
        _write(marker, {"schema_version":1,"status":"started","release_revision":index["release_revision"],"index_sha256":hashlib.sha256(index_path.read_bytes()).hexdigest()})
        verified={}
        for name,(destination,tag) in image_plan.items():
            item=index["components"][name]; source=item.get("image_ref"); digest=item.get("manifest_digest")
            subprocess.run(["docker","run","--rm","--env","REGISTRY_AUTH_FILE=/auth/config.json","--volume",f"{auth}:/auth:ro",tool,"copy","--all","docker://"+source,"docker://"+destination+":"+tag],check=True,env=env)
            got=subprocess.run(["aws","ecr","describe-images","--region",region,"--repository-name",destination.split('/',1)[1],"--image-ids","imageTag="+tag,"--query","imageDetails[0].imageDigest","--output","text"],check=True,capture_output=True,text=True,env=env).stdout.strip()
            if got != digest: raise MirrorError("destination image digest differs from release index")
            verified[name]={"image_ref":destination+"@"+got,"manifest_digest":got}
        for name,key in (("vault-chart","vault_chart"),("cert-manager-chart","cert_manager_chart")):
            item=index["components"][name]; url=item.get("approved_url"); sha=item.get("archive_sha256"); digest=item.get("expected_oci_manifest_digest"); tag=item.get("tag")
            if not isinstance(url,str) or not url.startswith("https://") or not re.fullmatch(r"[a-f0-9]{64}",sha or "") or not DIGEST.fullmatch(digest or ""): raise MirrorError("chart authority is invalid")
            archive=f"/work/{name}.tgz"; target="oci://"+repos[key].rsplit('/',1)[0]
            command='set -eu; curl --fail --location --silent --show-error --output "$1" "$2"; printf "%s  %s\\n" "$3" "$1" | sha256sum --check --status; helm push "$1" "$4"'
            subprocess.run(["docker","run","--rm","--env","HELM_REGISTRY_CONFIG=/auth/config.json","--volume",f"{auth}:/auth:ro","--volume",f"{work}:/work","--entrypoint","sh",chart_tool,"-c",command,"--",archive,url,sha,target],check=True,env=env)
            got=subprocess.run(["aws","ecr","describe-images","--region",region,"--repository-name",repos[key].split('/',1)[1],"--image-ids","imageTag="+tag,"--query","imageDetails[0].imageDigest","--output","text"],check=True,capture_output=True,text=True,env=env).stdout.strip()
            if got != digest: raise MirrorError("destination chart digest differs from release index")
            verified[name]={"image_ref":repos[key]+"@"+got,"manifest_digest":got,"version":item["version"]}
        binding={"schema_version":1,"aws_account_id":account,"aws_region":region,"deployment_name":discovery["deployment_name"],"release_revision":index["release_revision"],"index_sha256":hashlib.sha256(index_path.read_bytes()).hexdigest(),"artifacts":verified}
        vault_chart=index["components"]["vault-chart"]
        consumer={"schema_version":1,"aws_account_id":account,"aws_region":region,"deployment_name":discovery["deployment_name"],
                  "images":{"bootstrap":verified["vault-bootstrap"]["image_ref"],"server":verified["vault-server"]["image_ref"],"agent":verified["vault-server"]["image_ref"],"injector":verified["vault-injector"]["image_ref"],"audit_relay":verified["vault-audit-relay"]["image_ref"]},
                  "chart":{"version":vault_chart["version"],"digest":verified["vault-chart"]["manifest_digest"]}}
        _write(manifest,consumer); _write(receipt,{**binding,"status":"verified"}); _write(state_dir/"vault-artifact-mirror-verified.json",{**binding,"status":"verified"})
        return manifest
    finally:
        shutil.rmtree(work,ignore_errors=True)

_mirror_impl = mirror
def mirror(*args, **kwargs):
    try:
        return _mirror_impl(*args, **kwargs)
    except subprocess.CalledProcessError as error:
        raise MirrorError("artifact mirror command failed; the outcome requires reconciliation") from error

