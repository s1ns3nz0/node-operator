# The database cannot read a validator keystore, its password, or TLS material.
path "kv/data/validators/hoodi/REPLACE_WITH_VALIDATOR_SET/runtime/slashing-db-password" {
  capabilities = ["read"]
}
path "kv/metadata/validators/*" { capabilities = ["deny"] }
path "transit/*" { capabilities = ["deny"] }
path "auth/*" { capabilities = ["deny"] }
path "sys/*" { capabilities = ["deny"] }
