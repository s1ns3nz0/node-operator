#!/usr/bin/env python3
"""Render, but never apply, an isolated PostgreSQL 16 slashing-DB clone rehearsal."""
import argparse
import json
import re
import sys

NAME = "hoodi-001-db-rehearsal"
NAMESPACE = "validator-operations"
AZ = "ap-northeast-2c"
VOLUME = re.compile(r"^vol-(?:[0-9a-f]{8}|[0-9a-f]{17})$")
IMAGE = re.compile(r"^106760547719\.dkr\.ecr\.ap-northeast-2\.amazonaws\.com/node-operator-baseline-validator-runtime-postgres@sha256:[0-9a-f]{64}$")

def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(64)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--volume-id", required=True)
    parser.add_argument("--image", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    if not VOLUME.fullmatch(args.volume_id) or args.volume_id == "vol-095adf3e093cb529e": fail("volume ID must be an isolated lowercase EBS clone ID")
    if not IMAGE.fullmatch(args.image): fail("image must be the reviewed same-account PostgreSQL ECR digest")
    if not args.output.startswith("/"): fail("output must be an absolute path")
    labels = {"app.kubernetes.io/component": "slashing-db-rehearsal", "node-operator.io/rehearsal": "isolated-clone"}
    security = {"runAsNonRoot": True, "runAsUser": 999, "runAsGroup": 999, "fsGroup": 999, "fsGroupChangePolicy": "OnRootMismatch", "seccompProfile": {"type": "RuntimeDefault"}}
    container_security = {"allowPrivilegeEscalation": False, "readOnlyRootFilesystem": True, "capabilities": {"drop": ["ALL"]}}
    init_resources = {"requests": {"cpu": "100m", "memory": "128Mi"}, "limits": {"cpu": "500m", "memory": "256Mi"}}
    postgres_resources = {"requests": {"cpu": "100m", "memory": "256Mi"}, "limits": {"cpu": "1", "memory": "1Gi"}}
    pgdata = "/var/lib/postgresql/data/pgdata"
    data_mount = {"name": "data", "mountPath": "/var/lib/postgresql/data"}
    pod = {"apiVersion":"v1","kind":"Pod","metadata":{"name":NAME,"namespace":NAMESPACE,"labels":labels},"spec":{
        "automountServiceAccountToken":False,"restartPolicy":"Never","terminationGracePeriodSeconds":60,"securityContext":security,
        "initContainers":[{"name":"verify-restored-cluster","image":args.image,"command":["sh","-ec",f"test \"$(cat {pgdata}/PG_VERSION)\" = 16; state=\"$(LC_ALL=C pg_controldata {pgdata} | awk -F: '$1 ~ /^Database cluster state[[:space:]]*$/ {{v=$2; sub(/^[[:space:]]*/, \"\", v); sub(/[[:space:]]*$/, \"\", v); print v; exit}}')\"; test \"$state\" = 'shut down'"],"resources":init_resources,"securityContext":container_security,"volumeMounts":[data_mount]}],
        "containers":[{"name":"postgres","image":args.image,"command":["postgres","-D",pgdata,"-c","listen_addresses=","-c","unix_socket_directories=/var/run/postgresql"],"resources":postgres_resources,"securityContext":container_security,"volumeMounts":[data_mount,{"name":"socket","mountPath":"/var/run/postgresql"},{"name":"tmp","mountPath":"/tmp"}]}],
        "volumes":[{"name":"data","persistentVolumeClaim":{"claimName":NAME}},{"name":"socket","emptyDir":{"sizeLimit":"64Mi"}},{"name":"tmp","emptyDir":{"sizeLimit":"64Mi"}}]}}
    objects = [
      {"apiVersion":"v1","kind":"PersistentVolume","metadata":{"name":NAME,"labels":labels},"spec":{"capacity":{"storage":"50Gi"},"volumeMode":"Filesystem","accessModes":["ReadWriteOnce"],"persistentVolumeReclaimPolicy":"Retain","storageClassName":"","csi":{"driver":"ebs.csi.aws.com","volumeHandle":args.volume_id,"fsType":"ext4"},"nodeAffinity":{"required":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"topology.kubernetes.io/zone","operator":"In","values":[AZ]}]}]}}}},
      {"apiVersion":"v1","kind":"PersistentVolumeClaim","metadata":{"name":NAME,"namespace":NAMESPACE,"labels":labels},"spec":{"accessModes":["ReadWriteOnce"],"storageClassName":"","volumeName":NAME,"resources":{"requests":{"storage":"50Gi"}}}},
      {"apiVersion":"networking.k8s.io/v1","kind":"NetworkPolicy","metadata":{"name":NAME,"namespace":NAMESPACE,"labels":labels},"spec":{"podSelector":{"matchLabels":labels},"policyTypes":["Ingress","Egress"]}}, pod]
    with open(args.output, "x", encoding="utf-8") as handle: json.dump({"apiVersion":"v1","kind":"List","items":objects}, handle, indent=2); handle.write("\n")

if __name__ == "__main__": main()
