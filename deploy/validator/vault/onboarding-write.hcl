# Template only: replace the validator-set segment during the approved,
# one-time ceremony. This policy is write-only and cannot be reused by runtime
# signing identities.
path "kv/data/validators/hoodi/REPLACE_WITH_VALIDATOR_SET/onboarding/keystore" {
  capabilities = ["create", "update"]
}

path "kv/data/validators/hoodi/REPLACE_WITH_VALIDATOR_SET/onboarding/password" {
  capabilities = ["create", "update"]
}

path "transit/*" {
  capabilities = ["deny"]
}

path "sys/*" {
  capabilities = ["deny"]
}
