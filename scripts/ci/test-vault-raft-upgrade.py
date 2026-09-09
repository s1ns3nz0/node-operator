#!/usr/bin/env python3
"""Isolated synthetic Raft upgrade/restore rehearsal; never uses live Vault."""
import json
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

OLD = "sha256:20ff3ed4a4da750d1be0757c82e0a10accc00c26c157bde3a694f2b227300caf"
NEW = "sha256:5463f9d70fe71b897b165e019dbc1e85aeaa8271130572bd060729dc124ff51f"


def run(*args, allowed=(0,)):
    result = subprocess.run(args, capture_output=True, text=True, timeout=120)
    if result.returncode not in allowed:
        # CLI arguments/responses can contain synthetic root/unseal material.
        raise RuntimeError(f"fixture command failed (exit {result.returncode}); output withheld")
    return result.stdout


def main():
    owner = "hoodi-raft-test-" + uuid.uuid4().hex[:12]
    volume = None
    containers = []
    current = None
    token = None
    with tempfile.TemporaryDirectory(prefix="hoodi-raft-config-") as scratch:
        config = Path(scratch) / "server.hcl"
        config.write_text('''disable_mlock = true
api_addr = "http://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
listener "tcp" {
  address = "127.0.0.1:8200"
  tls_disable = true
}
storage "raft" {
  path = "/data/raft"
  node_id = "synthetic-one"
}
''')
        config.chmod(0o444)

        def cli(*args, allowed=(0,), authenticated=True):
            env = ["-e", "VAULT_ADDR=http://127.0.0.1:8200"]
            if authenticated and token:
                env += ["-e", "VAULT_TOKEN=" + token]
            return run("docker", "exec", *env, current, "/bin/vault", *args,
                       allowed=allowed)

        def start(image):
            nonlocal current
            current = run("docker", "run", "-d", "--platform", "linux/amd64",
                          "--label", "node-operator.test-owner=" + owner,
                          "--network", "none", "--read-only", "--cap-drop", "ALL",
                          "--security-opt", "no-new-privileges", "--user", "100:1000",
                          "--mount", f"type=volume,src={volume},dst=/data",
                          "--mount", f"type=bind,src={config},dst=/fixture/server.hcl,readonly",
                          "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,uid=100,gid=1000",
                          "--entrypoint", "/bin/vault", image,
                          "server", "-config=/fixture/server.hcl").strip()
            containers.append(current)
            for _ in range(40):
                if run("docker", "inspect", "--format", "{{.State.Running}}", current).strip() != "true":
                    break
                try:
                    return json.loads(cli("status", "-format=json", allowed=(0, 2),
                                          authenticated=False))
                except (RuntimeError, json.JSONDecodeError):
                    time.sleep(1)
            diagnostics = run("docker", "inspect", "--format",
                              "status={{.State.Status}} exit={{.State.ExitCode}}", current)
            raise RuntimeError("synthetic Vault did not become reachable; "
                               + diagnostics + "; logs withheld")

        try:
            for image in (OLD, NEW):
                assert run("docker", "image", "inspect", image,
                           "--format", "{{.Id}}").strip() == image
            volume = run("docker", "volume", "create", "--label",
                         "node-operator.test-owner=" + owner, owner).strip()
            run("docker", "run", "--rm", "--network", "none", "--read-only",
                "--cap-drop", "ALL", "--cap-add", "CHOWN", "--user", "0:0",
                "--security-opt", "no-new-privileges", "--mount",
                f"type=volume,src={volume},dst=/data", "--entrypoint", "/bin/sh",
                NEW, "-ec", "mkdir /data/raft && chown 100:1000 /data /data/raft")
            assert start(OLD)["initialized"] is False
            initialized = json.loads(cli("operator", "init", "-key-shares=1",
                                         "-key-threshold=1", "-format=json"))
            token = initialized["root_token"]
            share = initialized["unseal_keys_b64"][0]
            cli("operator", "unseal", share)
            cli("secrets", "enable", "-path=synthetic", "kv-v2")
            cli("kv", "put", "synthetic/checkpoint", "value=before-upgrade")
            cli("operator", "raft", "snapshot", "save", "/data/before.snap")
            run("docker", "stop", "--time", "30", current)
            assert start(NEW)["initialized"] is True
            cli("operator", "unseal", share)
            assert cli("kv", "get", "-field=value", "synthetic/checkpoint").strip() == "before-upgrade"
            cli("kv", "put", "synthetic/checkpoint", "value=after-upgrade")
            cli("operator", "raft", "snapshot", "restore", "/data/before.snap")
            for _ in range(40):
                try:
                    if cli("kv", "get", "-field=value", "synthetic/checkpoint").strip() == "before-upgrade":
                        break
                except RuntimeError:
                    pass
                time.sleep(1)
            else:
                raise RuntimeError("restored synthetic value was not observed")
            print(json.dumps({"result": "passed", "old_image": OLD, "new_image": NEW,
                              "checks": ["fresh Raft initialization", "old-process stopped before new start",
                                         "retained KV after upgrade", "old snapshot restores pre-mutation KV"],
                              "scope": "synthetic single-node compatibility, not live HA migration or recovery-key ceremony"}))
        finally:
            for container in reversed(containers):
                run("docker", "rm", "-f", container)
            if volume:
                run("docker", "volume", "rm", volume)


if __name__ == "__main__":
    main()
