# Vault Raft bootstrap debrief

## Conclusion

The committed source-only remediation is structurally safe: it adds a private
mTLS `retry_join` route for an empty Vault Raft member, reuses the existing
read-only TLS mount, and preserves TLS, private `ClusterIP`, and KMS-seal
boundaries. It is not yet evidence that a future Helm reconciliation will
bootstrap a new follower successfully. The task graph still marks encoding in
progress and validation, publication, and reconciliation pending.

## Observed evidence

- The relevant diff from `origin/main` is limited to the reviewed
  `vault-values.example.yaml`, its structural contract test, and the task
  bundle. It does not add a secret value, public listener, static AWS
  credential, deployment command, or external-action script.
- The new `retry_join` is inside the Raft storage stanza and points at the
  private Vault-0 service over HTTPS. It supplies CA, client certificate, and
  client-key paths from the pre-existing `/vault/userconfig/vault-tls`
  read-only mount.
- The updated GitOps contract asserts all four join values and retains checks
  for TLS enabled, three replicas, `ClusterIP`, disabled ingress, private ECR
  image references, immutable tags, and the KMS seal placeholder.
- The task evidence records that two empty Raft followers were manually joined
  to Vault-0 with mTLS and that all three pods became Ready with an active,
  KMS-unsealed Raft HA Vault. It records no recovery key, root token, or TLS
  private material.
- Independent local checks passed: `npm run test:vault-gitops-contract`,
  `bash scripts/ci/test-toolchain-image-release.sh`, `npm run harness:check`
  (52 graphs), `npm run harness:verify`, and `git diff --check origin/main...HEAD`.
  The toolchain check confirms `vault-values.example.yaml` participates in the
  Vault bootstrap image input hash.
- `harness:verify` exited successfully. Its output includes expected denials
  for deliberately insecure policy fixtures and an incomplete-OSV-report
  diagnostic, so it does not establish an OSV result or a hosted reconciliation
  result.

## Inference and limits

Using the already-approved private DNS name and the chart's existing TLS files
is consistent with reproducing the successful manual mTLS join without
introducing a public or plaintext fallback. The source change should let a
fresh, empty follower attempt that route when the reviewed values are applied.

This is not proof of runtime behavior. The evidence does not show the rendered
chart, an actual post-change Helm reconciliation, retry behavior during leader
unavailability, a newly provisioned empty PVC, or a live mTLS join performed
by the updated configuration. The bundle also leaves `validation` empty and
the task graph non-complete, which correctly prevents treating the source
commit as completion.

## Remaining completion conditions

1. Record the applicable validation evidence in the task bundle and advance
   the graph only after integration review.
2. Publish the reviewed bootstrap toolchain image if its changed input is to be
   consumed.
3. Under the stated authority, reconcile the reviewed values through the
   approved private path and record non-sensitive readback that the Raft
   bootstrap contract works for an empty follower.

No cloud, GitHub, deployment, secret, publication, merge, or push action was
taken by this reviewer.
