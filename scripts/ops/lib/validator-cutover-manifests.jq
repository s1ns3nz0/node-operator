# Input is kubectl dry-run JSON (possibly multiple documents, slurped by jq).
def objects: .[] | if .kind == "List" then .items[] else . end;
def identity: [.kind, .metadata.namespace, .metadata.name];
("validator-" + $set + "-") as $prefix |
[
  ["Service", "validator-operations", "slashing-db"],
  ["StatefulSet", "validator-operations", "slashing-db"],
  ["Service", "validator-operations", "remote-signer-direct"],
  ["Deployment", "validator-operations", "remote-signer"],
  ["Lease", "validator-operations", "primary"],
  ["NetworkPolicy", "validator-operations", "signer-dependencies"],
  ["NetworkPolicy", "validator-operations", "db-dependencies"],
  ["NetworkPolicy", "validator-operations", "signer-ingress"],
  ["NetworkPolicy", "validator-operations", "db-ingress"],
  ["Service", "validator-operations", "client-headless"],
  ["StatefulSet", "validator-operations", "client"],
  ["NetworkPolicy", "validator-operations", "client-egress"],
  ["NetworkPolicy", "node-operator", "beacon-ingress"]
] | map(.[2] = ($prefix + .[2])) | sort as $expected |
$documents | [objects] as $objects |
([$objects[] | identity] | sort) == $expected and
all($objects[];
  if .kind == "Deployment" then .spec.replicas == 0
  elif .kind == "StatefulSet" and .metadata.name == ($prefix + "client") then .spec.replicas == 0
  elif .kind == "StatefulSet" then .spec.replicas == 1
  else true end)
