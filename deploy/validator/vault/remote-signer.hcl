# Template only: instantiate one policy per environment and validator set.
# The remote signer reads only its runtime key records. It has no metadata list,
# delete, export, release-Transit, CI, or cross-set access.
path "kv/data/validators/hoodi/REPLACE_WITH_VALIDATOR_SET/runtime/keystore" {
  capabilities = ["read"]
}

path "kv/data/validators/hoodi/REPLACE_WITH_VALIDATOR_SET/runtime/password" {
  capabilities = ["read"]
}

path "kv/metadata/validators/*" {
  capabilities = ["deny"]
}

path "transit/*" {
  capabilities = ["deny"]
}

path "auth/*" {
  capabilities = ["deny"]
}

path "sys/*" {
  capabilities = ["deny"]
}
