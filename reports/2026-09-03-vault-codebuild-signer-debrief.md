# Clean-room debrief: Vault CodeBuild signer

## Implemented boundary

The change scaffolds, but does not activate, a private release-signing path.
A tag-bound GitHub OIDC JWT on an ephemeral private runner may obtain one
short-lived Vault-issued AWS lease. That lease can place signer input, start
and inspect only the named CodeBuild signer, and read its constrained output.
CodeBuild holds the separate Vault Transit sign-and-verify capability; keys
are not exportable. The emitted non-secret verification record binds the
Transit-verified signature to the release bundle, provenance digest and
subject, source revision, builder identity, and CodeBuild build ID. The local
gate recomputes the evidence bindings and fails closed on absent, invalid,
mismatched, or credential-like evidence.

The GitOps and operating contracts require private Vault networking and TLS,
ephemeral hardened runners, narrowly bound JWT claims, audit correlation, and
recovery evidence. The release workflow itself remains unchanged.

## Validation evidence

The completed task bundle records these successful checks:

- `bash scripts/ci/test-vault-release-contract.sh`
- `npm run test:vault-gitops-contract`
- `npm run test:vault-release-verification-gate`
- `npm run test:vault-private-release-runner-contract`
- `npm run harness:check`
- `git diff --check`

## Intentional exclusions and authorized next step

No AWS, EKS, Vault, GitHub environment/runner, Terraform, or release-workflow
change was performed; no key or credential was created, exported, or stored.
The task contract explicitly excludes AWS apply, Vault production deployment,
and key export.

The remaining authorized next step is a separately approved operational
rollout: provision and validate the private runner and Vault route, complete
the required GitOps/Terraform and recovery controls, then authorize the
release-workflow transition only after its failure-path evidence is reviewed.
