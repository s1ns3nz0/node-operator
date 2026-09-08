## Summary

- Pin both CI scanner consumers to the image published from the reviewed PR128 merge commit.
- Require the same immutable lowercase SHA-256 image reference in both workflows; regression fixtures reject mismatch, floating tags and duplicate bindings.
- Record protected approval/merge, publisher success and direct registry/source-content verification separately from activation.

## Publication evidence

- Reviewed source: PR128, merge commit `90c7b2a3743abd3df25a7438b3eeeda07434fe0f`.
- Successful publisher: https://github.com/s1ns3nz0/node-operator/actions/runs/34191107978
- Image: `ghcr.io/s1ns3nz0/node-operator/security-scanners@sha256:df5078a48b7536b5f64e99b97cf6bfceab7c1638fcd534f499600d4d27fd836d`.
- Manifest/config/layer hashes checked; image input label matched the source algorithm; embedded collector bytes matched the exact merged source, including corrected OSV invocation.

## Validation and limits

- Focused collector contract, immutable-pin negative fixtures, publisher isolation, script quality and harness checks pass. Policy adapter passed 67/67 tests and rejected intended insecure fixtures.
- Registry metadata and the small collector layer were inspected without executing the full image locally. This is not independent signature/provenance verification or a complete runtime security pass.
- The trusted default-branch evidence gate still uses the predecessor image until this separate promotion is reviewed and merged. Do not treat that known bootstrap failure as a passing result or silently waive any required protection.
- No PR127/GitOps merge, cloud deployment, secret access or protection change is included. This draft is preparation only; merging requires separate review and authorization.
