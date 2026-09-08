#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workflow="$script_dir/../../.github/workflows/ci-security.yml"
gate_workflow="$script_dir/../../.github/workflows/opa-pr-gate.yml"
review_workflow="$script_dir/../../.github/workflows/ci-review-refresh.yml"
review_handler="$script_dir/../../.github/workflows/ci-review-refresh-handler.yml"

check_scanner_images() {
  local scanner_workflow="$1"
  local scanner_gate_workflow="$2"
  local scanner_image
  local gate_scanner_image
  local immutable_scanner_image_pattern='^ghcr\.io/s1ns3nz0/node-operator/security-scanners@sha256:[0-9a-f]{64}$'

  scanner_image="$(sed -nE 's/^[[:space:]]*SCANNER_IMAGE:[[:space:]]*([^[:space:]#]+).*$/\1/p' "$scanner_workflow")"
  gate_scanner_image="$(sed -nE 's/^[[:space:]]*SCANNER_IMAGE:[[:space:]]*([^[:space:]#]+).*$/\1/p' "$scanner_gate_workflow")"

  if ! [[ "$scanner_image" =~ $immutable_scanner_image_pattern ]]; then
    printf 'ci-security scanner image must use one immutable lowercase SHA-256 reference\n' >&2
    return 1
  fi

  if ! [[ "$gate_scanner_image" =~ $immutable_scanner_image_pattern ]]; then
    printf 'opa-pr-gate scanner image must use one immutable lowercase SHA-256 reference\n' >&2
    return 1
  fi

  if [[ "$scanner_image" != "$gate_scanner_image" ]]; then
    printf 'scanner image references must match across security workflows\n' >&2
    return 1
  fi
}

run_scanner_image_guard_tests() {
  local test_dir
  local ci_fixture
  local gate_fixture
  local valid_image='ghcr.io/s1ns3nz0/node-operator/security-scanners@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

  test_dir="$(mktemp -d)"
  ci_fixture="$test_dir/ci-security.yml"
  gate_fixture="$test_dir/opa-pr-gate.yml"
  trap 'rm -rf "$test_dir"' RETURN

  printf 'SCANNER_IMAGE: %s\n' "$valid_image" > "$ci_fixture"
  printf 'SCANNER_IMAGE: %s\n' "$valid_image" > "$gate_fixture"
  check_scanner_images "$ci_fixture" "$gate_fixture"

  printf 'SCANNER_IMAGE: ghcr.io/s1ns3nz0/node-operator/security-scanners@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n' > "$gate_fixture"
  if check_scanner_images "$ci_fixture" "$gate_fixture" 2>/dev/null; then
    printf 'scanner image guard accepted mismatched image references\n' >&2
    return 1
  fi

  printf 'SCANNER_IMAGE: ghcr.io/s1ns3nz0/node-operator/security-scanners:latest\n' > "$ci_fixture"
  printf 'SCANNER_IMAGE: ghcr.io/s1ns3nz0/node-operator/security-scanners:latest\n' > "$gate_fixture"
  if check_scanner_images "$ci_fixture" "$gate_fixture" 2>/dev/null; then
    printf 'scanner image guard accepted a floating tag\n' >&2
    return 1
  fi

  printf 'SCANNER_IMAGE: %s\nSCANNER_IMAGE: %s\n' "$valid_image" "$valid_image" > "$ci_fixture"
  printf 'SCANNER_IMAGE: %s\n' "$valid_image" > "$gate_fixture"
  if check_scanner_images "$ci_fixture" "$gate_fixture" 2>/dev/null; then
    printf 'scanner image guard accepted multiple SCANNER_IMAGE bindings\n' >&2
    return 1
  fi
}

if [[ "${1:-}" == '--self-test-scanner-images' ]]; then
  run_scanner_image_guard_tests
  printf 'PASS: scanner image guard rejects invalid bindings.\n'
  exit 0
fi

check_scanner_images "$workflow" "$gate_workflow"

# The scanner produces the sole uploadable evidence in a non-hidden directory,
# rather than a hidden checkout path. This preserves upload-artifact's safe
# default (hidden files excluded) and prevents an accidental workspace-wide
# upload. The scanner mounts the workspace read-only and /evidence separately.
grep -Fq 'EVIDENCE_ROOT: ${{ github.workspace }}/security-evidence' "$workflow"
grep -Fq 'path: ${{ env.EVIDENCE_ROOT }}' "$workflow"
grep -Fq -- '--volume "$GITHUB_WORKSPACE:/workspace:ro"' "$workflow"
grep -Fq -- '--volume "$EVIDENCE_ROOT:/evidence"' "$workflow"
if grep -Fq 'include-hidden-files: true' "$workflow"; then
  printf 'security evidence upload must not include hidden files\n' >&2
  exit 1
fi

test "$(grep -Fc 'checks: write' "$gate_workflow")" -eq 2
grep -Fq 'resolve-pr-evidence-context.sh' "$gate_workflow"
grep -Fq 'ref: ${{ steps.context.outputs.trusted_sha }}' "$gate_workflow"
grep -Fq 'Collect trusted security evidence from untrusted source' "$gate_workflow"
grep -Fq -- '--volume "$GITHUB_WORKSPACE/.pr-source:/workspace:ro"' "$gate_workflow"
grep -Fq -- '--volume "$RUNNER_TEMP/head-security-evidence:/evidence"' "$gate_workflow"
grep -Fq -- '--env SEMGREP_RULES=/trusted-config/semgrep.yml' "$gate_workflow"
grep -Fq -- '--env GITLEAKS_CONFIG=/trusted-config/gitleaks.toml' "$gate_workflow"
grep -Fq -- '--volume "$GITHUB_WORKSPACE/.semgrep/ci.yml:/trusted-config/semgrep.yml:ro"' "$gate_workflow"
grep -Fq -- '--volume "$GITHUB_WORKSPACE/scripts/ci/trusted-scanner/gitleaks.toml:/trusted-config/gitleaks.toml:ro"' "$gate_workflow"
grep -Fq 'Reject pull-request scanner policy replacement' "$gate_workflow"
grep -Fq '*:osv-scanner.toml|*:.osv-scanner.toml' "$gate_workflow"
grep -Fq 'git -C .pr-source diff --name-only -z' "$gate_workflow"
grep -Fq 'read -r -d' "$gate_workflow"
grep -Fq -- '--env CHECKOV_CONFIG_FILE=/trusted-config/checkov.yml' "$gate_workflow"
grep -Fq -- '--env OSV_CONFIG_FILE=/trusted-config/osv-scanner.toml' "$gate_workflow"
grep -Fq -- 'osv-scanner scan source --config="$OSV_CONFIG_FILE" --no-ignore' "$script_dir/collect-pr-evidence.sh"
grep -Fq -- '--disable-nosem --no-git-ignore' "$script_dir/collect-pr-evidence.sh"
grep -Fq -- 'zizmor --offline --no-config' "$script_dir/collect-pr-evidence.sh"
grep -Fq 'untrusted-zizmor-suppression' "$script_dir/collect-pr-evidence.sh"
if grep -Fq 'Download scanner evidence from the completed PR run' "$gate_workflow"; then
  printf 'trusted decision must not consume a pull-request-controlled scanner artifact\n' >&2
  exit 1
fi
grep -Fq 'Publish exact-SHA evidence check' "$gate_workflow"
grep -Fq 'Publish failed exact-SHA evidence check' "$gate_workflow"
grep -Fq 'publish-pr-evidence-check.sh "$SUBJECT_SHA"' "$gate_workflow"

printf 'PASS: scanner evidence is confined to a non-hidden dedicated directory.\n'

grep -Fq 'pull_request_review:' "$review_workflow"
grep -Fq 'permissions: {}' "$review_workflow"
if grep -Fq 'actions/checkout' "$review_workflow"; then
  printf 'review signal must not checkout pull-request context\n' >&2
  exit 1
fi
if grep -Eq '(actions|checks|contents|pull-requests): write|request-pr-evidence-refresh' "$review_workflow"; then
  printf 'review signal must not have write permissions or invoke repository code\n' >&2
  exit 1
fi
grep -Fq 'workflows: [CI Evidence Review Signal]' "$review_handler"
grep -Fq 'actions: write' "$review_handler"
grep -Fq 'request-pr-evidence-refresh.sh?ref=$GITHUB_SHA' "$review_handler"
grep -Fq '"$trusted_script" "$GITHUB_EVENT_PATH"' "$review_handler"
