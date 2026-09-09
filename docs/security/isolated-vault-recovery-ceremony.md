# Isolated real-snapshot recovery: execution boundaries

This is preparation for the approved Hoodi recovery rehearsal, not evidence
that a restore or upgrade has succeeded. The temporary recovery host exists;
the original EKS Vault cluster remains unchanged.

## Temporary auto-unseal access

The isolated role needs Encrypt, Decrypt and DescribeKey on the original seal
key to open the restored barrier. Its IAM policy alone is insufficient because
the existing seal key policy does not delegate this use through account IAM.
Do not replace that policy, reuse the live Vault role, or grant CreateGrant to
the recovery host.

`scripts/ops/manage-isolated-vault-recovery-grant.py` confines grant management
to the reviewed account, key, recovery role, grant name and expiry. Run its
help before use. The default is a read-only plan; create and revoke must be
explicit. A separately provisioned, temporary AWS profile assuming the existing
KMS administrator role is required. Do not put credentials in source control
or shell arguments. Acquiring that session is not implemented by this helper.

The administrator session should itself be restricted to DescribeKey,
ListGrants and RevokeGrant on the exact seal key and CreateGrant constrained to
the exact recovery principal and the three required operations. No key-policy
mutation or cryptographic operation is needed by the grant manager.
The session-policy template is
`deploy/vault/bootstrap/isolated-recovery-grant-session-policy.json`. It must
be passed when acquiring the administrator session; the helper cannot prove
that an existing profile was issued with this session policy. AWS authorizes
RevokeGrant at key scope, so the helper's exact grant identity validation is
also required to avoid revoking an unrelated grant on that key.
The IAM set condition permits nonempty subsets of the three operations; it
does not require all three. The helper must request and validate exactly all
three and reject an existing named grant with a subset or additional operation.
The session policy also prevents CreateGrant after the approved expiry using
AWS time, while keeping inspect/revoke available for cleanup after expiry.

Grants do not provide a wall-clock expiry. The recovery host's explicit IAM
deny after `2026-09-10T12:00:00Z` is a separate safeguard; grant revocation and
resource cleanup remain mandatory. Creation and revocation are eventually
consistent. A successful revoke request is not proof that every endpoint has
already denied use. The helper does not print or persist GrantToken.

Sources: [AWS KMS grants](https://docs.aws.amazon.com/kms/latest/developerguide/grants.html),
[CreateGrant API](https://docs.aws.amazon.com/kms/latest/APIReference/API_CreateGrant.html).

## Required before snapshot restore

- Reconfirm the isolated VPC, no live peer routes, private endpoints, scoped
  host role, IAM expiry deny, and current SSM health. The grant helper is not a
  replacement for these checks.
- Keep exact S3 version and checksum verification on the isolated encrypted
  host. Never download the real snapshot to the workstation or CI.
- Pin the old and candidate Vault image digests to reviewed evidence. Do not
  use a mutable tag or treat a synthetic Shamir test as an AWS KMS restore.
- Design the local-only listener and credentials path explicitly: IMDSv2 hop
  limit one prevents ordinary Docker bridge access to instance credentials.
  Do not increase it or enable broad host networking without a reviewed design.
- Recreate isolated file/socket audit destinations before restored requests.
  Do not reconnect restored audit sinks or retry_join configuration to live
  services. No recovered validator keys may reach a signer.
- Recovery shares, generated tokens and any restored credentials stay solely
  within the user-operated terminal ceremony. Revoke newly generated tokens;
  remember that the snapshot can contain credentials revoked after it was taken.
- Prove restore health and metadata-only checks, then the candidate upgrade.
  Do not read/export custody secrets merely to prove that restore succeeded.
- Stop the isolated Vault, revoke the exact temporary grant, verify cleanup
  and retain only non-sensitive evidence. Full infrastructure teardown requires
  its own reviewed destroy plan; expiry tags do not perform teardown.

Until these execution requirements are implemented and reviewed, do not start
the real clone, upgrade the original cluster, or activate the validator client.
