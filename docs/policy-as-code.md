# Open-source policy-as-code CI/CD guide

## Purpose and boundary

This repository uses an evidence-first policy gate: tools detect facts, normalize them into JSON, and OPA/Rego decides whether the change may proceed. A scanner result alone is never the release decision. Policy is version-controlled, tested, CODEOWNERS-protected, and evaluated fail-closed.

This guide implements the activities described in the project’s policy-as-code reference across commit, merge, build, release, runtime, and governance. It is a portfolio implementation, not a compliance certification and not authorization to deploy to AWS.

```text
source / SCM posture / scanner outputs / build attestation
                       │
                       ▼
              normalized JSON evidence
                       │
                       ▼
            OPA (`opa eval` / Conftest)
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
      block           warn       approved exception
```

## Repository layout

```text
policy/
  data/tiers.json                 # threshold and trusted-builder data
  data/exceptions.json            # rule, owner, rationale, artifact, expiry
  commit/*.rego                   # commit and source evidence decisions
  merge/*.rego                    # PR, workflow and SCM posture decisions
  build/*.rego                    # IaC, SAST, SCA, SBOM decisions
  release/*.rego                  # artifact/provenance/deployment eligibility
  runtime/*.rego                  # admission-ready Kubernetes policies
  tests/**/*_test.rego            # passing and failing fixtures
scripts/policy/                   # collector/normalizer entry points
scripts/ci/                       # one-purpose CI commands invoked by workflows
evidence/                         # CI artifacts keyed by commit SHA or digest
```

The local policy directory is deliberate for a single portfolio repository. Extract a shared bundle only after more than one repository needs the same policy set.

## Thin-workflow convention

Workflow YAML describes only the pipeline: trigger, least-privilege permissions, job dependency, pinned third-party action, cache/artifact boundary, and one call to a repository script per logical step. It must not contain multiline shell implementations, embedded Rego, JSON transformation, duplicated scanner flags, or policy branching. This makes the visible workflow a readable control-flow diagram and keeps all reusable behavior testable outside GitHub Actions.

```text
.github/workflows/pull-request.yml
  ├── collect: scripts/ci/collect-pr-evidence.sh
  ├── normalize: scripts/ci/normalize-evidence.sh
  ├── decide: scripts/ci/evaluate-policy.sh
  └── publish: scripts/ci/publish-evidence.sh
```

Initial script boundaries are:

- `scripts/ci/collect-{gitleaks,osv,semgrep,zizmor,checkov,terraform}.sh`: invoke one tool with pinned, documented options and emit its JSON.
- `scripts/ci/collect-scm-posture.sh`: collect only policy-required GitHub API fields and write normalized posture input.
- `scripts/ci/normalize-evidence.sh`: validate producer schemas, bind commit SHA/digest and collection time, and create OPA input; missing or malformed producer output fails.
- `scripts/ci/evaluate-policy.sh`: run `opa eval`/Conftest and emit the structured decision.
- `scripts/ci/publish-evidence.sh`: create SARIF/JSON artifacts without publishing sensitive values.
- `scripts/ci/verify-release-evidence.sh`: reuse the same normalizer/evaluator for SBOM, provenance, signature, and scan-age inputs.

Scripts use Bash with strict shell options and `jq` for JSON shaping, pass ShellCheck, accept paths and explicit environment variables, and write only declared artifact paths. Shared functions live in a small `scripts/ci/lib/` module only when used by more than one command; workflows never copy scanner invocations or policy logic.

## Activities, evidence, and enforcement

| Stage | Activity to detect | Open-source evidence producer | OPA decision | Enforcement |
| --- | --- | --- | --- | --- |
| Commit | secrets never enter source | Gitleaks JSON | any finding blocks | pre-commit and required PR check |
| Commit | dependencies are completely resolved and within policy | OSV-Scanner JSON plus lockfile inventory | incomplete dependency graph, prohibited license, or threshold breach blocks | required PR check |
| Commit | code coverage matches every language/configuration in use | Semgrep JSON, Checkov JSON, language inventory | missing required scanner coverage blocks | required PR check |
| Commit | sensitive paths have independent owners | changed-file list, CODEOWNERS, PR-review data | missing owner approval blocks | required PR check |
| Merge | commits are signed and verified | GitHub commit API response | unsigned/unverified protected-branch commit blocks | required PR check and branch setting |
| Merge | self-approval and insufficient review are prevented | GitHub PR/review/branch-protection API response | author approval, insufficient reviews, or stale head-SHA checks block | branch protection plus required check |
| Merge | workflows are safe before execution | Zizmor JSON and parsed workflow YAML | unpinned action, excessive permissions, unsafe trigger, or untrusted secret reach blocks | required PR check |
| Merge | repository settings do not drift | OpenSSF Scorecard JSON plus GitHub API collector | protection, review, signing, or workflow posture drift warns/blocks by policy class | scheduled required posture workflow |
| Build | Terraform and manifests meet security configuration rules | Checkov JSON for Terraform and Kubernetes | failed IaC policy blocks unless a valid exception exists | required PR check |
| Build | source/static vulnerabilities are within the approved threshold | Semgrep and OSV-Scanner JSON | blocking findings or truncated/incomplete scans block | required PR check |
| Build | artifact has SBOM, digest and provenance | Syft CycloneDX/SPDX SBOM, build metadata, SLSA provenance | missing/mismatched subject digest or untrusted builder blocks | build/release gate |
| Release | image/artifact is signed and the exact digest is eligible | Cosign verification JSON, provenance, scan/SBOM evidence | unsigned, wrong digest, stale scan, or blocked finding blocks | release gate; no deployment in phase 1 |
| Runtime | Kubernetes manifests remain within declared policy | Conftest/OPA fixture and rendered-manifest input; later Gatekeeper audit/admission result | privileged, mutable-image, host-access, missing limits, or prohibited network policy blocks | render gate now; admission gate only after separate deployment approval |
| Governance | rules, thresholds, exceptions, and decisions remain accountable | `opa test`, policy metadata, exception register, decision JSON | untested rule, expired exception, missing owner/rationale, or unclassified violation blocks | policy PR and all gates |

## Tooling contract

All tools are open source and generate machine-readable output. Initial pinned versions are selected when implementation starts, recorded in the workflow as immutable release versions or full action commit SHAs, and updated only through reviewed dependency-update pull requests.

- **OPA / Conftest:** final policy engine and configuration evaluator.
- **Checkov:** Terraform and Kubernetes misconfiguration detection; its JSON is input to Rego, not the sole pass/fail rule.
- **Gitleaks:** secret detection.
- **OSV-Scanner:** lockfile/dependency vulnerability and resolution evidence.
- **Semgrep Community Edition:** SAST evidence for supported source languages and scripts.
- **Zizmor:** GitHub Actions workflow security evidence.
- **OpenSSF Scorecard:** scheduled repository posture evidence.
- **Syft:** SBOM creation; **Grype** may add image/SBOM vulnerability evidence.
- **Cosign:** artifact signing and verification; **SLSA provenance** records builder/source/digest linkage.

No proprietary SaaS API key is needed for these gates. GitHub API posture collection uses the job’s least-privilege `GITHUB_TOKEN`; its collector is a trusted pipeline component and emits only the normalized fields that Rego consumes.

## Policy interface

Each collector writes one JSON object with `schema_version`, `commit_sha` or `artifact_digest`, `collected_at`, `tool`, and `result`. The normalizer constructs a single OPA input:

```json
{
  "subject": {"commit_sha": "…", "artifact_digest": "sha256:…"},
  "evidence": {"checkov": {}, "gitleaks": {}, "osv": {}, "semgrep": {}, "zizmor": {}, "scorecard": {}},
  "scm": {"pull_request": {}, "branch_protection": {}, "reviews": {}, "workflow_files": []},
  "artifact": {"sbom": {}, "provenance": {}, "signature": {}, "scan": {}},
  "runtime": {"rendered_manifests": []},
  "policy": {"tiers": {}, "exceptions": {}}
}
```

Rego returns structured violations with `id`, `class`, `reason`, `subject`, and `evidence_ref`. Classes are `block`, `warn`, and `require-approval`. A failed collector or missing evidence is a `block`, not a clean result. CI fails only on `block`; it retains `warn` decisions as review evidence.

## Exceptions and change control

Exceptions are data, never edits that disable a rule. Each entry names the rule, affected digest or path, owner, rationale, linked issue, and RFC 3339 expiry. OPA rejects expired or incomplete entries. `policy/**`, `.github/workflows/**`, release configuration, and the exception register require CODEOWNERS review by `@fjybjinsu`; branch protection rejects author self-approval. Every Rego module has at least one passing and one failing fixture exercised by `opa test`. This is account separation for the portfolio, not an assertion of independent-human review.

The initial portfolio tier blocks deterministic integrity failures: secrets, missing required evidence, unpinned third-party actions, unsafe workflow triggers, public exposure, encryption failures, privileged workloads, mutable images, invalid Terraform, and expired exceptions. OPA also blocks every Critical vulnerability and High findings with an available fix; Medium/Low findings warn. These thresholds are policy data, not hard-coded. Exceptions require rule, subject, owner, rationale, linked issue, and an RFC 3339 expiry no later than 30 days after approval.

## Delivery sequence

1. Establish policy layout, thin workflow convention, data schema, `opa test`, Conftest, script fixture tests, and JSON normalizer fixtures.
2. Add required PR evidence producers: Gitleaks, OSV-Scanner, Semgrep, Checkov, and Zizmor.
3. Add Rego commit/merge/build decisions and make their OPA result a required status check.
4. Add scheduled GitHub posture collection and Scorecard evidence; never run it using untrusted fork code.
5. Add Syft/Grype, Cosign verification, and SLSA provenance checks as a release-eligibility gate. It produces evidence but does not publish or deploy in this phase.
6. Add rendered-manifest Conftest checks. Gatekeeper admission/audit integration remains disabled until AWS/EKS deployment is separately authorized.

## Evidence retention

Store only non-sensitive CI evidence keyed by commit SHA or artifact digest for 90 days. SARIF/JSON summaries are allowed; raw scanner logs, secret candidates, credentials, and sensitive payloads must never be logged or retained.
