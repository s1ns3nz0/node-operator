# Release signer buildspec shell debrief

Reviewed clean-room inputs: task bundle at commit `cbb5a83` (including its
recorded local checks) and that commit's diff. No external systems, secrets, or
production resources were accessed.

## Observed

- The recorded failing CodeBuild build reached `DOWNLOAD_SOURCE`; `/bin/sh`
  then rejected `set -o pipefail` before signing.
- Commit `cbb5a83` adds `env.shell: bash` to
  `deploy/vault/buildspec-release-sign.yml`, whose build commands use
  `set -euo pipefail`.
- The signer-toolchain contract test now fails if the exact Bash declaration is
  absent.
- The bundle records successful Ruby YAML parsing, the signer-toolchain,
  release-verification-gate, release-activation, and script-quality tests, and
  `npm run harness:check`.
- The task contract and graph still mark the task active; the graph leaves
  validation/merge/release pending.

## Inference

The change directly addresses the documented shell incompatibility and the new
structural test should prevent removal of the Bash selection. The recorded
local checks provide confidence in configuration shape and regression coverage.

## Not established by reviewed evidence

A post-change CodeBuild execution, a successful signer artifact, merge, or a
new protected-tag release is not recorded in this bundle. Those operational
acceptance outcomes remain unverified.
