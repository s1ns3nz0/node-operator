# Validator operation use cases and key boundaries

## Non-negotiable separation

The release Transit key, GitHub/App credentials, Vault root/recovery material,
AWS roles, Ethereum validator signing keys, and Ethereum withdrawal credentials
are different security domains. A successful CI release must never authorize a
validator signature. A validator remote signer must never read CI, Vault admin,
or withdrawal material.

## UC-1: Non-validating Hoodi client operation

**Goal:** run Nethermind and Prysm for sync, API observation, and P2P health.

**Keys:** no validator signing key and no withdrawal credential. The workload
uses only image-pull identity and any narrowly scoped telemetry credential.

**Vault:** client policy cannot read `kv/validators/*`, cannot call a validator
signing endpoint, and cannot access Transit release signing.

**Acceptance:** client pods Ready; attempts to use validator paths are denied.

## UC-2: Validator onboarding / deposit preparation

**Goal:** generate validator credentials in an operator-controlled, isolated
ceremony and submit a deposit only after independent verification.

**Keys:** an EIP-2335 validator keystore plus password, and a withdrawal
credential. Neither belongs in Git, CI, Terraform, container images, logs, or
Kubernetes Secret manifests. Withdrawal credentials are never mounted into the
validator workload.

**Vault:** store the encrypted keystore and password as separate versioned
records under an environment and validator-set-specific path. A one-time
ceremony role writes; the runtime signer role cannot read either record.

**Acceptance:** deposit data is independently verified; only hashes, public
keys, approval IDs, and non-secret ceremony evidence are retained.

## UC-3: Active validator signing through a remote signer

**Goal:** a consensus client requests slashable duties while the private key
remains confined to a dedicated signer workload.

**Keys:** the remote signer alone may decrypt/use the validator keystore. The
Prysm validator client has no keystore file or broad Vault token; it may call
only its namespaced signer endpoint over mTLS or a workload-bound auth method.

**Vault:** issue a short-lived, audience-bound identity to the signer service
account; scope it to one validator-set path. Require an explicit policy deny
for list, delete, export, CI/release Transit paths, and all other validator
sets. Prefer an HSM-backed signer when value or assurance warrants it.

**Acceptance:** allowed signing duty succeeds; an unauthorized validator key,
direct Vault read from Prysm, and CI identity calling the signer all fail.

## UC-4: Slashing protection, failover, and restart

**Goal:** prevent double proposal/attestation while recovering a signer or
consensus client.

**Keys/data:** slashing-protection interchange data is security-critical state,
not a disposable cache. It is distinct from the validator key and needs
encrypted, integrity-checked backup.

**Vault:** do not treat Vault KV as a high-frequency slashing database. Use
the client/signer-supported slashing database, make one active signer the
lease holder, and require a verified export/import plus a deliberate fencing
handover before failover.

**Acceptance:** a simulated failover proves the old signer cannot sign after
fencing and the replacement imports verified history before it is enabled.

## UC-5: Rotation, voluntary exit, and compromise response

**Goal:** contain a suspected signer compromise or safely end validator duties.

**Keys:** withdrawal credentials are not routinely rotatable in the same way
as application credentials; their custody requires separate recovery approval.
Validator signing key replacement or voluntary exit must follow the network's
protocol and an operator-approved runbook.

**Vault:** revoke the affected signer identity and access policy first, fence
the signer, preserve audit evidence, and rotate only the relevant secret
version after recovery. Never delete signing or slashing evidence as an
incident shortcut.

**Acceptance:** signer API is denied after revocation, audit correlation is
preserved, and recovery is rehearsed without using production key material.
