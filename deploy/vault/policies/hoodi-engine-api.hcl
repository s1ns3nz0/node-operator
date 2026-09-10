# Shared per-node Engine API credential.  This policy is deliberately the only
# capability given to execution and consensus clients: no listing, mutation,
# Transit, auth administration, or validator-custody access is permitted.
path "kv/data/nodes/hoodi/engine-api-jwt" {
  capabilities = ["read"]
}

path "kv/metadata/*" { capabilities = ["deny"] }
path "transit/*" { capabilities = ["deny"] }
path "auth/*" { capabilities = ["deny"] }
path "sys/*" { capabilities = ["deny"] }
