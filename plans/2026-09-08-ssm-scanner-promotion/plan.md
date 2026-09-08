# Activate the verified file-aware collector

PR134 is merged and its main workflow published a source-bound scanner.
Independently verify immutable manifest/config hashes and source-input label,
replace both workflow pins without changing policy, then run tests and hosted
admission. After approval and normal merge, verify actual main CI uses the new
digest. SSM module changes and state migration stay in their separate task.

Hosted review found the legacy inline Zizmor suppression in the changed OPA
workflow. Remove that comment rather than bypass the collector. The underlying
dangerous-triggers warning remains visible and requires the separately reviewed
policy-only prerequisite PR136 on trusted main. Do not merge this promotion
until that prerequisite and exact-head admission pass. No workflow execution or
permissions are changed by the comment removal.
