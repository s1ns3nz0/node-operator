# Foundation backend ownership support

Requirement 5 needs an explicit encrypted remote state owner, not only a
private local import candidate. The tag-only reconciliation is applied and
the six-resource post-apply plan is no-drift; migration is not yet authorized.

Terra owns an isolated follow-up based on the reviewed existing-network mode.
Implementation is limited to an empty S3 backend declaration, non-secret
foundation backend example, operations migration documentation, release-bundle
inclusion and focused tests. No new generic deployment runner is needed in
this slice. Preserve the fresh mode and existing mode resource contracts.

Use the isolated key `node-operator/foundation-network/terraform.tfstate`,
explicit encryption/CMK and the verified bootstrap backend bucket/region/lock
table. Never embed credentials or copy the baseline state key. Document exact
init/migration commands, empty-destination guard, private backup, content and
resource-ID comparison, metadata handling and final no-drift. No force-copy.

Offline fixtures must explicitly override the S3 backend with a local backend
in temporary fixture configuration. `init -backend=false` alone is not proof
that a subsequent plan works. Execute a real local initialization/plan fixture
to verify this behavior, with no remote state or cloud write. Reuse cached
provider; do not download duplicate binaries on the nearly full disk.

Before any migration, independently review source changes and exact private
backend config, verify destination absence, protect the local state backup and
prove the configured role can perform encrypted backend read/write/locking.
Implementation approval alone authorizes no remote migration or apply.

## Subsequent exact migration approval

Root independently reviewed source `41bf8f9`, initialized local-backend staging
at `/private/tmp/node-operator-foundation-migrate.l8NDSm/module`, equal canonical
content, six exact resource IDs, and the candidate/config hashes reported by
the primary Sol-role owner. Existing role assumption succeeded using the same
trust condition as the earlier canary; the condition value stayed private.
Destination HeadObject returned 404 under that role.

Root authorized only normal `init -migrate-state` from this verified local
state to the isolated foundation key, with fresh hash/absence/ownership guards,
interactive prompt review, no force-copy, no resource apply, and mandatory
encrypted readback, content/identity comparison and refreshed no-drift plan.
No other state root is included. Migration success remains unproven until
those actual postconditions are checked.

## Source integration

The backend/existing-mode work began before source PR127 landed. Integrate it
in a separate worktree with a normal merge of current main; never replace main
with the old branch tree or interpret its missing newer files as deletions.
Review the resulting diff against main, preserve all newer CI/security work,
run focused backend/existing-mode/release tests, then create a separate PR.
PR131 remains frozen for its current-head approval proof.
