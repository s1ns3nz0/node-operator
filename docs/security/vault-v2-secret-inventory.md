# Vault v2 secret inventory

This is the authoritative inventory for Hoodi runtime custody. New workloads
must use the isolated mounts below; the historical `kv/` mount is rollback
only and must not receive new runtime records.

## `node-operator-runtime/` (KV v2)

| Path | Fields | Reader |
|---|---|---|
| `nodes/hoodi/engine-api-jwt` | `jwt` | Nethermind and Prysm Beacon only |
| `validators/hoodi/<set>/runtime/keystore` | `keystore` | Web3Signer only |
| `validators/hoodi/<set>/runtime/password` | `password` | Web3Signer only |
| `validators/hoodi/<set>/runtime/slashing-db-password` | `password` | Web3Signer and its PostgreSQL database only |
| `validators/hoodi/<set>/runtime/signer-tls` | `pkcs12_b64`, `password` | Web3Signer only |
| `validators/hoodi/<set>/runtime/client-tls` | `tls_crt_b64`, `tls_key_b64`, `ca_crt_b64` | Prysm validator client only |

No role may list metadata, read another validator set, or write at runtime.

## `node-operator-pki/` (PKI)

The issuer private key remains inside the PKI secrets engine. Workloads never
receive it. Only a reviewed rotation ceremony may issue signer/client mTLS
leaf certificates. The issuer is stable across normal leaf rotation; root or
issuer rotation is a separate recovery exercise. The client trust bundle and
known-client fingerprint are public configuration, not KV secrets.

## Never store in Vault

- validator mnemonic, withdrawal seed, Vault root/recovery/unseal material;
- Vault server TLS private key, bootstrap GitOps credential, or static AWS and
  GitHub credentials;
- projected Kubernetes, SSM, OIDC, or Vault child tokens;
- public validator key, withdrawal address, deposit hash, CA certificate, or
  known-client fingerprint.
