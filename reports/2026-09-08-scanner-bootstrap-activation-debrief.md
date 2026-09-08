# Clean-room debrief: scanner bootstrap activation

## Current stage

The earlier merge-admission block is resolved historically: bundle evidence records PR 128 as normally human-approved and merged at `90c7b2a3743abd3df25a7438b3eeeda07434fe0f`. The main publisher run `34191107978` is recorded as successful for both build and publish. Activation is **not** complete: the separate digest-promotion change remains prepared and unmerged.

## Independent observations

- I reviewed the current task bundle and only the relevant `origin/main` diff and three promotion files.
- The supplied publication JSON identifies the verified immutable image digest as `sha256:df5078a48b7536b5f64e99b97cf6bfceab7c1638fcd534f499600d4d27fd836d`.
- Correction: my prior mismatch finding is withdrawn. It was based on the unrelated repository worktree rather than this supplied task worktree. Here, both proposed workflow pins are exactly `sha256:df5078a48b7536b5f64e99b97cf6bfceab7c1638fcd534f499600d4d27fd836d`, matching the supplied verified digest (`both_match=true`). No source correction is indicated by this review.
- Locally observed in the supplied task worktree: `scripts/ci/test-ci-security-evidence-contract.sh` passed; `scripts/ci/test-ci-security-evidence-contract.sh --self-test-scanner-images` passed. The self-test covers valid binding acceptance and mismatch, floating, and duplicate binding rejection. These are bounded contract/self-test results only.

## Supplied external proof and limits

The bundle reports direct registry API verification of the manifest, config and 4,717-byte collector layer, including a collector-byte comparison with the exact merged source and matching input label/hash. It also reports that no full runtime image pull or execution was performed. Those are supplied external proof claims, not locally reproduced checks in this debrief.

This review does not claim cryptographic signature or provenance verification, a scanner runtime pass, or an overall CI/security-gate pass. The inherited security/compliance findings remain outside this bounded activation review.

## Required handoff

The separately prepared promotion still requires its independent review and normal merge admission; it is not merged or activated. Root Sol (`/root/scanner_bootstrap_activation`) remains the integration owner; no external action was taken here.
