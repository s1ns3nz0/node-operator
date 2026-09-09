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
