# Activate the verified file-aware collector

PR134 is merged and its main workflow published a source-bound scanner.
Independently verify immutable manifest/config hashes and source-input label,
replace both workflow pins without changing policy, then run tests and hosted
admission. After approval and normal merge, verify actual main CI uses the new
digest. SSM module changes and state migration stay in their separate task.
