# Scanner digest promotion clean-room debrief

## Scope and source

This clean-room review considered only the completed task bundle, the committed range `a9a1f7a3de147bff5863c2dd344fc251732a4835..75488ed6b0c3cd64c0728d30255787e89a765346`, and the recorded validation evidence.

The committed implementation changes exactly two workflow values: the immutable `security-scanners` digest in `CI Security` and `CI Evidence Gate`. Both replace `010ca69dc9d08d2d255c2e9d80b54544245fad8d85c670f723cce788e3bb16af` with `9f6300a37edb593aa09e0085f07787098079cbba75c01d0538aff99ebaac04ce`. The bundle binds that new digest to scanner publish run `34183851988` / job `101928506646` and records a successful anonymous GHCR HEAD observation, including the expected linux/amd64 entrypoint and image-input label `0e1290a5e22a954482acb978af0cf0fee944cd2cf1ee4e9058f3560532dc64c1`.

No control-plane, permission, trigger, checkout, scanner-policy, or artifact-handling behavior changed in the committed workflow diff. The pre-existing inline zizmor ignore remains in the OPA workflow; it was not added or broadened by this promotion. The only recorded external mutations were the authorized feature-branch push at `75488ed6b0c3cd64c0728d30255787e89a765346` and draft PR `#126`. The bundle records no merge, image publication, branch-rule change, cloud mutation, or secret access.

## Validation observed

The bundle records passing focused contracts for CI security evidence, scanner-image release, PR evidence checks, and script quality; `npm run harness:check` passed with 82 graphs; `npm run harness:verify` passed with 67/67 Rego tests and expected Conftest fixture rejection; and `git diff --check` passed.

PR `#126` also recorded five standard checks passing for the exact head. That is not an approval to promote or merge: the trusted exact-head `CI Evidence Decision` check failed with `block=0` and `require_approval=1`, specifically because `review.sensitive-path` requires CODEOWNER `fjybjinsu`. This is the expected fail-closed result before required review, rather than evidence of a policy bypass or scan failure.

The PR-produced scanner artifact recorded zero gitleaks and Semgrep findings and one zizmor finding. The bundle identifies that finding as `untrusted-zizmor-suppression`, attributable to the existing inline ignore in the changed OPA workflow YAML. The active trusted gate deliberately uses the default-branch workflow/pin, which is still the predecessor image digest; it does not consume the PR-produced artifact. Therefore this result must not be described as activation of the new image in the trusted gate.

## Decision and pending work

The narrow two-pin change is consistent with the recorded published-image binding and preserves the security boundaries shown by the diff. Its promotion is conditionally ready only after the required CODEOWNER approval and subsequent activation on the trusted default branch. Pending review/activation means no claim is warranted that the new digest is already the active trusted-gate image.

This review does not claim closure of all High or Medium findings. The recorded M1 release-eligibility compatibility issue remains open: the actual custom-check `details_url` is `/runs/101930466432`, while `verify-release-source-eligibility` accepts only `/actions/runs/<workflow-run-id>`. It is correctly a separate follow-up and was not fixed in this PR. If it is not resolved, M1 live eligibility must not be claimed.
