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

## Existing validator deployment

For an already active validator, preserve the BLS keystore, its password, and
the PostgreSQL password exactly. The slashing DB PVC and signing history must
survive the deployment. Fresh onboarding generates a database password and
must not be used to replace the existing validator's records.

`scripts/ops/copy-hoodi-custody-to-runtime-v2.sh --validator-set hoodi-001`
is the administrator-only data preparation step. It detects the legacy mount
version, validates all three source records before writing, uses CAS=0, checks
read-back equality, and refuses conflicting destination values. It leaves
legacy records, policies, workloads, and PVCs unchanged. Re-running after a
partial copy is supported when already-created values match.

Remaining live acceptance requirements:

- Complete the user-controlled recovery ceremony and confirm root revocation.
- Prepare all six runtime records, issuing transport certificates from PKI.
- Fence the existing validator before changing workload authentication.
- Apply the immutable Engine chart and validator manifests; retain the DB PVC.
- Verify Vault Agent initialization, Engine authentication, signer mTLS and
  successful DB authentication before resuming the client.
- Verify a subsequent canonical validator duty and collect non-secret evidence.
- Remove superseded Kubernetes credential Secrets only after these checks.

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
