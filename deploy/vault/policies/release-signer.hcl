# Applied to the short-lived CodeBuild signer identity.
# The transit key never leaves Vault; signing is the only permitted operation.
path "transit/sign/node-operator-release" {
  capabilities = ["update"]
}

# Explicitly do not grant key read/export, delete, rotate, or config access.
