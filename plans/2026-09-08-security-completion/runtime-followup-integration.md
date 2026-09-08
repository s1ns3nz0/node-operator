# Runtime fixes: stacked source integration

Scope: combine the independently reviewed, already deployed signer HTTP Host
fix (`4224883`) and four narrow cross-pool ingress rules (`b9c7761`) on an
isolated branch based on frozen PR127 head `cb4e002`. Do not change PR127.

Root owns the integration worktree. The primary Sol-role owner retains final
security judgment. Existing changes made by others must be preserved.

Validation: inspect the combined diff, execute both contract suites,
run shell syntax and Terraform format checks, and validate the task harness.
The two contract suites were not invoked by hosted CI; add both to the required
quality job so future regressions cannot pass using shell lint alone. This
adds one workflow file to the reviewed five-file runtime delta. The access
contract explicitly reports its optional Kyverno CLI suite as skipped when
unavailable; this does not claim independent Kyverno engine validation.
The actual runtime evidence remains authoritative: all four DAST targets
returned 200, but one passive alert means DAST still fails. Targeted four-rule
readback/no-drift is not a full baseline no-drift claim.

Allowed external action after successful checks: push the isolated branch and
create a draft stacked PR against PR127's branch. No deployment or merge is
part of this slice. After parent merge, retarget and rerun required checks.

Ops EBS representation and foundation ownership changes remain separate.

Hosted PR131 quality run `34202878737` exposed a real Linux portability defect:
the public CA installer hard-coded macOS `/private/tmp`. Extend this slice to
its installer only: honor `${TMPDIR:-/tmp}` for the same three mktemp files,
retaining exclusive creation and exact-file cleanup. The behavioral fixture
sets a custom TMPDIR and asserts the ConfigMap certificate paths use it. Do
not skip the CI test or create a macOS-specific directory on the runner.
