#!/usr/bin/env bash
set -euo pipefail

# Collect scanner results into compact, non-sensitive envelopes. The five scanner
# envelopes are the sole inputs accepted by normalize-evidence.sh. Scanner stdout,
# stderr, and full reports stay in a private temporary directory and are deleted.

if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
  printf 'usage: %s OUTPUT_DIRECTORY COMMIT_SHA [SOURCE_DIRECTORY] [BASE_SHA]\n' "$0" >&2
  exit 64
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"

output_directory="$1"
commit_sha="$2"
source_directory="${3:-$(repo_root)}"
base_sha="${4:-${PR_BASE_SHA:-}}"
collector_mode="${COLLECTOR_MODE:-all}"

[[ "$commit_sha" =~ ^[0-9a-f]{40}$ ]] || { printf 'commit SHA must be 40 lowercase hexadecimal characters\n' >&2; exit 64; }
require_command git
require_command jq
case "$collector_mode" in
  all)
    require_command gitleaks
    require_command osv-scanner
    require_command semgrep
    require_command zizmor
    require_command checkov
    if [ "${SKIP_TERRAFORM:-false}" != "true" ]; then require_command terraform; fi
    ;;
  terraform)
    require_command terraform
    ;;
  *)
    printf 'COLLECTOR_MODE must be all or terraform\n' >&2
    exit 64
    ;;
esac
git -C "$source_directory" rev-parse --is-inside-work-tree >/dev/null

umask 077
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$output_directory"

write_envelope() {
  local destination="$1" tool="$2" result_path="$3"
  jq -n --arg tool "$tool" --arg sha "$commit_sha" --arg collected_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --slurpfile result "$result_path" \
    '{schema_version:"v1", tool:$tool, commit_sha:$sha, collected_at:$collected_at, result:$result[0]}' > "$destination"
}

run_report() {
  local report_path="$1" log_path="$2"
  shift 2
  set +e
  "$@" > "$report_path" 2> "$log_path"
  collector_exit_code=$?
  set -e
}

require_json_report() {
  local tool="$1" report_path="$2"
  jq -e . "$report_path" >/dev/null 2>&1 || { printf '%s did not produce a valid JSON report\n' "$tool" >&2; exit 1; }
}

require_json_shape() {
  local tool="$1" report_path="$2" shape="$3"
  jq -e "$shape" "$report_path" >/dev/null 2>&1 || { printf '%s produced an incomplete JSON report\n' "$tool" >&2; exit 1; }
}

collect_gitleaks() {
  local report_path="$temporary_directory/gitleaks.json" result_path="$temporary_directory/gitleaks-result.json"
  set +e
  gitleaks detect --no-git --source "$source_directory" --redact=100 --report-format json --report-path "$report_path" --no-banner --no-color > "$temporary_directory/gitleaks.stdout" 2> "$temporary_directory/gitleaks.stderr"
  collector_exit_code=$?
  set -e
  [ "$collector_exit_code" -eq 0 ] || [ "$collector_exit_code" -eq 1 ] || { printf 'gitleaks failed before producing evidence\n' >&2; exit 1; }
  require_json_report gitleaks "$report_path"
  require_json_shape gitleaks "$report_path" 'type == "array"'
  # Never retain a raw Gitleaks result. Paths and rule identifiers are sufficient
  # for the policy decision and cannot reconstruct a detected secret.
  jq '[.[]? | {path:(.File // .file // "unknown"), rule_id:(.RuleID // .rule_id // "unknown")}]' "$report_path" \
    | jq -c '{findings:.}' > "$result_path"
  write_envelope "$output_directory/gitleaks.json" gitleaks "$result_path"
}

collect_osv() {
  local report_path="$temporary_directory/osv.json" result_path="$temporary_directory/osv-result.json"
  run_report "$report_path" "$temporary_directory/osv.stderr" osv-scanner scan source --format=json "$source_directory"
  if [ "$collector_exit_code" -eq 128 ] && grep -Fqx 'No package sources found, --help for usage information.' "$temporary_directory/osv.stderr"; then
    # OSV uses exit 128 when the repository contains no supported dependency
    # manifest. This is not a clean dependency scan: retain that distinction
    # in the evidence while allowing a dependency-free repository to proceed.
    printf '%s\n' '{"vulnerabilities":[],"status":"not_applicable","reason":"no_supported_dependency_manifests"}' > "$result_path"
    write_envelope "$output_directory/osv.json" osv "$result_path"
    return
  fi
  [ "$collector_exit_code" -eq 0 ] || [ "$collector_exit_code" -eq 1 ] || { printf 'osv-scanner failed before producing evidence\n' >&2; exit 1; }
  require_json_report osv "$report_path"
  require_json_shape osv "$report_path" '.results | type == "array"'
  # Retain only package and remediation metadata, never lockfile paths or full
  # advisory descriptions. Severity is preserved when the scanner supplies it.
  jq '[.results[]?.packages[]? as $package | $package.vulnerabilities[]? | {
        package: ($package.package.name // "unknown"),
        id: (.id // "unknown"),
        severity: ((.database_specific.severity // .severity // "UNKNOWN") | if type == "string" then . else "UNKNOWN" end),
        fix_available: ((.database_specific.fixed_version? // .fixed_version? // .fixed_versions?[0]? // null) != null)
      }]' "$report_path" | jq -c '{vulnerabilities:.}' > "$result_path"
  write_envelope "$output_directory/osv.json" osv "$result_path"
}

collect_semgrep() {
  local report_path="$temporary_directory/semgrep.json" result_path="$temporary_directory/semgrep-result.json"
  local semgrep_rules="${SEMGREP_RULES:-$source_directory/.semgrep/ci.yml}"
  require_file "$semgrep_rules"
  set +e
  semgrep scan --config "$semgrep_rules" --metrics=off --error --json-output "$report_path" "$source_directory" > "$temporary_directory/semgrep.stdout" 2> "$temporary_directory/semgrep.stderr"
  collector_exit_code=$?
  set -e
  [ "$collector_exit_code" -eq 0 ] || [ "$collector_exit_code" -eq 1 ] || { printf 'semgrep failed before producing evidence\n' >&2; exit 1; }
  require_json_report semgrep "$report_path"
  require_json_shape semgrep "$report_path" '.results | type == "array"'
  jq '[.results[]? | {
        path:(.path // "unknown"),
        rule_id:(.check_id // "unknown"),
        severity:(.extra.severity // "UNKNOWN")
      }]' "$report_path" | jq -c '{findings:.}' > "$result_path"
  write_envelope "$output_directory/semgrep.json" semgrep "$result_path"
}

collect_zizmor() {
  local report_path="$temporary_directory/zizmor.json" result_path="$temporary_directory/zizmor-result.json"
  run_report "$report_path" "$temporary_directory/zizmor.stderr" zizmor --offline --format=json-v1 "$source_directory"
  [ "$collector_exit_code" -eq 0 ] || [ "$collector_exit_code" -ge 10 ] || { printf 'zizmor failed before producing evidence\n' >&2; exit 1; }
  require_json_report zizmor "$report_path"
  require_json_shape zizmor "$report_path" 'type == "array"'
  jq '[.[]? | {
        path:(.locations[0].symbolic.key.Local.verbatim_path // "unknown"),
        rule_id:(.ident // "unknown"),
        message:(.desc // "unsafe workflow finding")
      }]' "$report_path" | jq -c '{findings:.}' > "$result_path"
  write_envelope "$output_directory/zizmor.json" zizmor "$result_path"
}

collect_checkov() {
  local report_path="$temporary_directory/checkov.json" result_path="$temporary_directory/checkov-result.json"
  run_report "$report_path" "$temporary_directory/checkov.stderr" checkov --directory "$source_directory" --framework terraform --output json --quiet
  [ "$collector_exit_code" -eq 0 ] || [ "$collector_exit_code" -eq 1 ] || { printf 'checkov failed before producing evidence\n' >&2; exit 1; }
  require_json_report checkov "$report_path"
  require_json_shape checkov "$report_path" '.results.failed_checks | type == "array"'
  jq '[.results.failed_checks[]? | {
        resource:(.resource // .resource_address // "unknown"),
        check_id:(.check_id // "unknown"),
        check_name:(.check_name // "IaC policy failure")
      }]' "$report_path" | jq -c '{failed_checks:.}' > "$result_path"
  write_envelope "$output_directory/checkov.json" checkov "$result_path"
}

collect_format() {
  local result_path="$temporary_directory/format-result.json"
  if [ -z "$base_sha" ]; then
    printf '%s\n' '{"status":"skipped","reason":"base SHA was not provided"}' > "$result_path"
  elif ! [[ "$base_sha" =~ ^[0-9a-f]{40}$ ]] || ! git -C "$source_directory" cat-file -e "${base_sha}^{commit}" 2>/dev/null; then
    printf '%s\n' '{"status":"unavailable","reason":"base SHA is not available locally"}' > "$result_path"
  else
    set +e
    git -C "$source_directory" diff --check "$base_sha" "$commit_sha" > "$temporary_directory/format.stdout" 2> "$temporary_directory/format.stderr"
    collector_exit_code=$?
    set -e
    if [ "$collector_exit_code" -eq 0 ]; then
      printf '%s\n' '{"status":"passed","check":"git-diff-check"}' > "$result_path"
    else
      printf '%s\n' '{"status":"failed","check":"git-diff-check"}' > "$result_path"
    fi
  fi
  write_envelope "$output_directory/format.json" format "$result_path"
}

collect_terraform() {
  local directories_path="$temporary_directory/terraform-directories" result_path="$temporary_directory/terraform-result.json"
  find "$source_directory" -type f -name '*.tf' -exec dirname {} \; | LC_ALL=C sort -u > "$directories_path"
  if [ ! -s "$directories_path" ]; then
    printf '%s\n' '{"status":"not_applicable","modules":[]}' > "$result_path"
    write_envelope "$output_directory/terraform.json" terraform "$result_path"
    return
  fi

  if [ -z "${TERRAFORM_PLUGIN_MIRROR:-}" ] || [ ! -d "$TERRAFORM_PLUGIN_MIRROR" ]; then
    printf '%s\n' '{"status":"failed","reason":"offline provider mirror is required"}' > "$result_path"
    write_envelope "$output_directory/terraform.json" terraform "$result_path"
    return
  fi

  cat > "$temporary_directory/terraformrc" <<EOF
provider_installation {
  filesystem_mirror {
    path = "$TERRAFORM_PLUGIN_MIRROR"
  }
  direct {
    exclude = ["*/*"]
  }
}
EOF

  : > "$temporary_directory/terraform-modules.ndjson"
  local index=0 module_directory init_exit validate_exit
  while IFS= read -r module_directory; do
    index=$((index + 1))
    set +e
    TF_CLI_CONFIG_FILE="$temporary_directory/terraformrc" TF_DATA_DIR="$temporary_directory/terraform-data-$index" terraform -chdir="$module_directory" init -backend=false -get=false -input=false -lockfile=readonly -no-color > "$temporary_directory/terraform-init-$index.stdout" 2> "$temporary_directory/terraform-init-$index.stderr"
    init_exit=$?
    if [ "$init_exit" -eq 0 ]; then
      TF_CLI_CONFIG_FILE="$temporary_directory/terraformrc" TF_DATA_DIR="$temporary_directory/terraform-data-$index" terraform -chdir="$module_directory" validate -json -no-color > "$temporary_directory/terraform-validate-$index.json" 2> "$temporary_directory/terraform-validate-$index.stderr"
      validate_exit=$?
    else
      validate_exit=1
    fi
    set -e
    if [ "$init_exit" -eq 0 ] && [ "$validate_exit" -eq 0 ] && jq -e '.valid == true' "$temporary_directory/terraform-validate-$index.json" >/dev/null 2>&1; then
      jq -n --arg module "${module_directory#"$source_directory"/}" '{module:$module,status:"passed"}' >> "$temporary_directory/terraform-modules.ndjson"
    else
      jq -n --arg module "${module_directory#"$source_directory"/}" '{module:$module,status:"failed"}' >> "$temporary_directory/terraform-modules.ndjson"
    fi
  done < "$directories_path"
  jq -s '{status:(if any(.[]; .status == "failed") then "failed" else "passed" end), modules:.}' "$temporary_directory/terraform-modules.ndjson" > "$result_path"
  write_envelope "$output_directory/terraform.json" terraform "$result_path"
}

if [ "$collector_mode" = "terraform" ]; then
  collect_terraform
  exit 0
fi

collect_gitleaks
collect_osv
collect_semgrep
collect_zizmor
collect_checkov
collect_format
if [ "${SKIP_TERRAFORM:-false}" = "true" ]; then
  jq -n --arg sha "$commit_sha" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{schema_version:"v1",tool:"terraform",commit_sha:$sha,collected_at:$at,result:{status:"not_run",modules:[]}}' > "$output_directory/terraform.json"
else
  collect_terraform
fi
