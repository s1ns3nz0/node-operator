# CI execution contract

Workflow YAML owns triggers, job dependencies, permissions, environments,
action pins, inputs and artifact upload configuration. Scripts own program
logic. A one-command invocation need not become another wrapper; a conditional,
loop or multi-stage release program belongs in a named script.

## Local checks

From the repository root:

```sh
npm run harness:bootstrap-policy-tools
export PATH="$PWD/.ci-tools/bin:$PATH"
bash scripts/ci/run-suite.sh policy
bash scripts/ci/run-suite.sh policy-contracts
bash scripts/ci/run-suite.sh uc5-offline
bash scripts/ci/run-suite.sh vault-runtime
bash scripts/ci/run-suite.sh vault-v2
bash scripts/ci/run-suite.sh isolated-recovery
bash scripts/ci/run-suite.sh operator-auth
```

Use `--list` after a suite name to inspect its ordered members without running
them. These manifests are the CI and local source of truth, not a second copy
of the workflow. Each member is reported and a failure immediately stops the
suite. UC-5 here means **offline regression tests**, not a live ceremony or a
claim that UC-5 validation is complete. Python 3, Bash and the suite's pinned
tools are prerequisites; this entrypoint never installs them implicitly.

Terraform requires Docker and the approved image (Docker may need registry
authentication to pull it). It uses the same wrapper locally and in CI:

```sh
bash scripts/ci/run-terraform-ci.sh all
# Optional subsets: root, runtime, modules, foundation, monitoring.
```

Every validation container uses a digest-pinned image, a read-only repository
mount, an output-only mount and `--network none`. Set `CI_OUTPUT_DIR` to choose
the evidence directory; otherwise CI uses `RUNNER_TEMP`, and local runs create
a temporary output directory. No production credentials are needed for these
offline checks. Authentication for a private image pull is separate from AWS
infrastructure access.

## Script organization

- `scripts/ci/test-*`: focused tests, each documenting its check objective.
- `scripts/ci/suites/*.txt`: ordered test groups shared by local and CI runs.
- `scripts/ci/workflows/`: workflow adapters and trusted evidence collection.
- `scripts/release/`: authenticated artifact build, mirror and publication
  programs. These are not part of a local test suite and must not be run as
  tests; they require explicit release authority and their workflow inputs.

Publishing adapters consume the workflow's explicit environment contract,
including GitHub OIDC/output channels. Do not pretend those external operations
are offline. Keep ordinary validation in independently executable test scripts.

## Workflow and job identities

`ci-*.yml` contains ordinary CI entrypoints. Policy rules and evidence contracts
share `ci-policy.yml` but keep distinct named jobs. Fence Security and Release
Integrity are reusable workflows; they remain at the top level of
`.github/workflows/` (GitHub does not support workflow subdirectories).

`image-release.yml` owns the scanner, toolchain, signing-fence and audit-relay
publisher jobs. Signing-fence evidence recognizes the two exact historical and
current workflow identities so already signed fence images remain verifiable;
new publications use only the `image-release.yml` identity. `*-mirror.yml` and
`release.yml` remain separate authority boundaries. `opa-pr-gate.yml` and
the review-signal/handler split retain trusted/untrusted execution separation.
Do not merge privileged publication into PR-controlled CI to reduce file count.

On push, a read-only selector compares the push baseline with the checked-out
commit. Only affected image families run; toolchains use a selected matrix rather
than rebuilding all six images. Missing baselines conservatively select all.
Publication requires main and successful prerequisites. Fence changes now also
trigger automatic security checks and protected publication on main, replacing
the previous manual-only Fence entrypoint. Existing protected environments remain.
Manual dispatch accepts `target=all`, `scanner`, `toolchains`, `fence`, `relay`,
or an individual toolchain name. The signed deployment bundle still uses
`release.yml`; combining image publishers does not publish a deployment bundle
or update running workloads.

Main branch protection currently requires `quality`, `scanners`, and
`CI Evidence Decision`. `Code Quality` and `Security Scans` are the readable
implementation jobs; always-run compatibility gates preserve those first two
required contexts and reject failed, cancelled or skipped dependencies. Release
eligibility additionally checks exact-SHA `Policy Rules`, `Terraform Validation`
and `Evidence Contracts` from their expected main-push workflows.

## Refactor verification

`test-ci-entrypoints.py` exercises suite ordering, failure propagation and
container isolation without Docker or cloud access. `test-ci-suite-ownership.py`
checks ownership after expanding suite manifests. Presentation checks protect
target-oriented labels and event identities. Source-contract tests may use
`lib/workflow-source.py` to inspect only scripts literally invoked by a workflow;
this static view complements tests and is not proof of live execution.
