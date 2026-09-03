# Clean-room debrief: ECR foundation live plan

## Scope and independence

This is an independent Terra review of the task bundle
`plans/2026-09-03-ecr-foundation-live-plan/`, the ECR signer mirror contract,
and the stated execution evidence.  No AWS, Terraform, image registry, Vault,
EKS, GitHub, or other external call was made for this debrief.  This report is
not an approval to apply.

## Observed evidence

- AWS STS identified caller account `106760547719` as
  `arn:aws:iam::106760547719:user/jsyang`.
- Terraform ran in the local pinned `terraform-validation` image.  The image,
  rather than the host environment, defined `/opt/terraform-plugin-mirror` and
  the direct-download denial.
- Backend initialization succeeded.  The plan ran with state locking disabled,
  saved its temporary plan artifact, and did not run `terraform apply`.
- The rendered plan JSON has SHA-256
  `fed96dde273deb86f5bea65162c6f098b58971bf1db5253937dc98abe2bff87f`.
- The plan JSON reports 104 creates, zero changes, and zero destroys.  Review
  found no NAT gateway, internet gateway, public subnet, or public-boundary
  violation in the planned output.
- The ECR mirror contract keeps the feature disabled by default.  When enabled,
  its foundation consists of five creates: a KMS key and alias, immutable
  scan-on-push ECR repository, GitHub OIDC role, and that role's policy.

## Assessment and inference

The strict foundation-only gate expects exactly those five ECR/KMS/OIDC
creates.  The observed 104 planned creates include baseline mutations beyond
that allowance, so the gate outcome is **BLOCKED**.

The 104-create outcome alone cannot conclusively distinguish an absent managed
baseline from a plan/state selection that does not include an existing managed
baseline; doing so requires state inspection, which is outside this
clean-room review.  That uncertainty does not change the result: the actual
plan outcome is not foundation-only and must not proceed to apply under this
task's authorization.

The absence of the specified public-network boundary violations is a positive
review observation, but it is not sufficient to override the strict mutation
gate or to authorize an apply.

## Required disposition

Do not apply this plan.  Before a later separately authorized review, inspect
the approved state/workspace and input selection, reconcile the baseline, and
produce a new saved plan whose action set satisfies the exact foundation-only
allowance (or obtain explicit authorization for a wider reviewed baseline
plan).

## Local validation

- `git show --check`: pass.
