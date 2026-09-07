# Vault signer trust debrief

Observed: the internal Vault NLB listens on TCP 8200; the private signer can
authenticate with Vault AWS auth only when both client signing and Vault
verification use regional STS; and a non-secret CodeBuild probe completed an
AWS-authenticated Transit sign and verify with the internal CA verified.

The durable change requires a Secrets Manager interface endpoint, reads only
the public Vault CA by ARN, writes it to a mode-0600 temporary file, and never
uses `VAULT_SKIP_VERIFY`. No Vault token or raw signature was included in this
report or CI evidence.
