# Vault server candidate

Full Vault 2.1.0 source build pinned to commit and archive checksum, using Go
1.26.6, x/crypto 0.56.0 and thrift 0.24.0. Final module files are hash checked.
This is separate from the agent-only dispatcher. Upstream generate-root and
snapshot-inspection command tests run during the build. Module/dependency
inventories and license are retained in `/usr/share/vault/`.

The local candidate `sha256:5463f9d70fe71b897b165e019dbc1e85aeaa8271130572bd060729dc124ff51f`
scanned Critical=0, High=0, Medium=3 and Unknown=1 with no ignored findings.
See the task evidence for the raw scan hash and build log. This is not a
trusted release, and no live Vault server has been changed.

Before rollout, require isolated Raft backup/restore and auth/audit tests,
assessment of GO-2026-5932, and a reviewed recovery ceremony transition.
Vault 2.x generate-root/rekey authentication requirements differ from the
existing recovery-share-only workflow; do not bypass them or assume that
holding recovery shares alone preserves operational access. Never copy live
Raft data, tokens or recovery shares into a Docker build context.

`python3 scripts/ci/test-vault-raft-upgrade.py` reuses the two frozen images
without rebuilding. The synthetic single-node Shamir rehearsal verifies data
retention and snapshot restore, plus a short-lived exact-endpoint token minted
before upgrade. On 2.1, no/invalid tokens fail; the scoped token cannot read KV
or create tokens, but it and the synthetic share can complete root generation.
The generated root is revoked and rejection verified.

Restoring a Raft snapshot also restores its token state: the test proves the
pre-snapshot ceremony token becomes valid again and revokes it again. The
post-snapshot generated root remains absent. All task-owned containers and the
synthetic volume are removed. This is not a live HA/KMS recovery-key test.

Before upgrading the real server, establish and test the operator's renewable
authentication path while the old server is still available. Existing
recovery-share-only wrappers are not ready for 2.1; a one-off expiring token
does not solve future recovery access. Do not enable unauthenticated endpoint
access or retain a long-lived root token to avoid this migration prerequisite.
