# Vault publication preparation

1. Confirm PR144 merge and preserve exact local Server/Agent images.
2. Recheck immutable local IDs, binary hashes, image configuration and retained scan hashes against merged evidence. Do not rebuild.
3. Record proposed repository/tag targets, explicitly distinguishing local image IDs from not-yet-verified registry manifest digests.
4. Review existing publisher permissions and remote proof-binding requirements.
5. Request task-level authorization for two candidate pushes before any publication. These are not deployment-approved images or CI build provenance.

After publication: read back manifest digests, review updated exact-candidate and applicability bindings, run hosted read-only verification, then implement honest signing/verification gates before separately authorized live rollout.
