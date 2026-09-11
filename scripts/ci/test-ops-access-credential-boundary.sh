#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
entrypoint="$root/scripts/release/node-operator-ops-access.sh"
real_python="$(command -v python3)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/ops-access-credentials.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/private"
chmod 700 "$scratch/private"
: > "$scratch/config.tfvars"
: > "$scratch/backend.hcl"
printf '{"aws_region":"ap-northeast-1"}\n' > "$scratch/ops-access.tfvars.json"
: > "$scratch/ops-access.backend.hcl"
: > "$scratch/private/unused-plan"
mkdir -p "$scratch/mock-root/infra/ops-access" "$scratch/mock-root/scripts/ci"
printf '#!/usr/bin/env bash\nexit 0\n' > "$scratch/mock-root/scripts/ci/check-ops-access-ssm-retention-plan.sh"
chmod +x "$scratch/mock-root/scripts/ci/check-ops-access-ssm-retention-plan.sh"

cat > "$scratch/bin/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'aws profile=%s command=%s\n' "${AWS_PROFILE:-}" "$*" >> "$MOCK_TRACE"
case "${AWS_PROFILE:-}" in
  state-role) printf '%s\n' '{"Account":"106760547719","Arn":"arn:aws:sts::106760547719:assumed-role/NodeOperatorTerraformApply/backend-test"}' ;;
  provider-read) printf '%s\n' '{"Account":"106760547719","Arn":"arn:aws:sts::106760547719:assumed-role/NodeOperatorProviderRead/provider-test"}' ;;
  *) exit 1 ;;
esac
EOF
cat > "$scratch/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'terraform profile=%s command=%s\n' "${AWS_PROFILE:-}" "$*" >> "$MOCK_TRACE"
printf 'terraform-env cli=%s data=%s workspace=%s log=%s variable=%s config=%s cache=%s input=%s automation=%s\n' "${TF_CLI_ARGS:-}" "${TF_DATA_DIR:-}" "${TF_WORKSPACE:-}" "${TF_LOG:-}" "${TF_VAR_name:-}" "${TF_CLI_CONFIG_FILE:-}" "${TF_PLUGIN_CACHE_DIR:-}" "${TF_INPUT:-}" "${TF_IN_AUTOMATION:-}" >> "$MOCK_TRACE"
case " $* " in
  *' show -json '*) printf '{}\n' ;;
  *' output -raw instance_id '*) printf 'i-0123abcd\n' ;;
  *' apply '*)
    case "${MOCK_RACE_MODE:-}" in
      directory) mkdir "$MOCK_RACE_SESSION_HANDOFF" ;;
      symlink-directory) ln -s "$MOCK_RACE_DIRECTORY" "$MOCK_RACE_SESSION_HANDOFF" ;;
    esac
    ;;
esac
EOF
cat > "$scratch/bin/python3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
"$OPS_REAL_PYTHON" "$@"
if [ "${MOCK_POST_LINK_SWAP:-false}" = true ]; then
  rm -f "$MOCK_POST_LINK_TARGET"
  ln -s "$MOCK_POST_LINK_VICTIM" "$MOCK_POST_LINK_TARGET"
fi
EOF
chmod +x "$scratch/bin/aws" "$scratch/bin/terraform" "$scratch/bin/python3"

common=(destroy --root "$root" --config "$scratch/config.tfvars" --backend-config "$scratch/backend.hcl" --plan-file "$scratch/private/unused-plan")
separated=(
  --backend-profile state-role
  --expected-backend-principal-arn arn:aws:iam::106760547719:role/NodeOperatorTerraformApply
  --provider-profile provider-read
  --expected-provider-principal-arn arn:aws:iam::106760547719:role/NodeOperatorProviderRead
)

# Destroy remains disabled, but initialization proves the two credential paths
# are separately forwarded after both exact identities pass.
if PATH="$scratch/bin:$PATH" MOCK_TRACE="$scratch/trace" OPS_REAL_PYTHON="$real_python" TF_CLI_ARGS=-refresh=false TF_DATA_DIR=/unsafe TF_WORKSPACE=unsafe TF_LOG=TRACE TF_VAR_name=unsafe TF_CLI_CONFIG_FILE=/unsafe/config TF_PLUGIN_CACHE_DIR=/unsafe/cache TF_INPUT=1 TF_IN_AUTOMATION=0 \
  bash "$entrypoint" "${common[@]}" "${separated[@]}" >/dev/null 2>&1; then
  printf 'direct destroy unexpectedly succeeded\n' >&2
  exit 1
fi
grep -Fq 'aws profile=state-role command=sts get-caller-identity --output json' "$scratch/trace"
grep -Fq 'aws profile=provider-read command=sts get-caller-identity --output json' "$scratch/trace"
grep -Fq 'terraform profile=provider-read command=-chdir=' "$scratch/trace"
grep -Fq -- '-backend-config=profile=state-role' "$scratch/trace"
grep -Fq -- '-lockfile=readonly' "$scratch/trace"
grep -Fq 'terraform-env cli= data= workspace= log= variable= config= cache= input= automation=' "$scratch/trace"

before="$(wc -l < "$scratch/trace" | tr -d ' ')"
if PATH="$scratch/bin:$PATH" MOCK_TRACE="$scratch/trace" bash "$entrypoint" "${common[@]}" \
  "${separated[@]:0:6}" --expected-provider-principal-arn arn:aws:iam::106760547719:role/WrongRole >/dev/null 2>&1; then
  printf 'mismatched provider role unexpectedly passed\n' >&2
  exit 1
fi
after="$(wc -l < "$scratch/trace" | tr -d ' ')"
test "$after" -eq $((before + 2)) # both STS checks ran; Terraform did not.

if PATH="$scratch/bin:$PATH" MOCK_TRACE="$scratch/trace" bash "$entrypoint" "${common[@]}" \
  --backend-profile state-role >/dev/null 2>&1; then
  printf 'partial credential separation unexpectedly passed\n' >&2
  exit 1
fi
if PATH="$scratch/bin:$PATH" MOCK_TRACE="$scratch/trace" bash "$entrypoint" "${common[@]}" \
  --backend-profile state-role --expected-backend-principal-arn arn:aws:iam::106760547719:role/NodeOperatorTerraformApply \
  --provider-profile state-role --expected-provider-principal-arn arn:aws:iam::106760547719:role/NodeOperatorTerraformApply >/dev/null 2>&1; then
  printf 'identical backend and provider identity unexpectedly passed as separated\n' >&2
  exit 1
fi
if PATH="$scratch/bin:$PATH" MOCK_TRACE="$scratch/trace" AWS_ACCESS_KEY_ID=redacted bash "$entrypoint" \
  "${common[@]}" "${separated[@]}" >/dev/null 2>&1; then
  printf 'exported AWS credential unexpectedly passed\n' >&2
  exit 1
fi
before_handoff="$(wc -l < "$scratch/trace" | tr -d ' ')"
plan="$scratch/private/preexisting-session-plan"; printf 'reviewed-plan\n' > "$plan"
sha="$(shasum -a 256 "$plan" | awk '{print $1}')"
inputs_parent="$(cd "$scratch" && pwd -P)"
jq -n --arg config "$inputs_parent/ops-access.tfvars.json" --arg backend "$inputs_parent/ops-access.backend.hcl" \
  '{schema_version:1,cluster_name:"node-operator",config:$config,backend_config:$backend}' > "$scratch/ops-access-inputs.json"
session="$scratch/private/session.json"; printf '{}\n' > "$session"
if PATH="$scratch/bin:$PATH" MOCK_TRACE="$scratch/trace" TF_CLI_ARGS=-refresh=false TF_DATA_DIR=/unsafe TF_WORKSPACE=unsafe TF_LOG=TRACE TF_VAR_name=unsafe \
  bash "$entrypoint" apply --root "$root" --inputs "$scratch/ops-access-inputs.json" --plan-file "$plan" --expected-sha "$sha" --session-handoff "$session" >/dev/null 2>&1; then
  printf 'preexisting session handoff unexpectedly passed\n' >&2; exit 1
fi
[ "$(wc -l < "$scratch/trace" | tr -d ' ')" = "$before_handoff" ] || { printf 'preexisting session handoff reached Terraform\n' >&2; exit 1; }
rm -f "$session"; ln -s "$scratch/elsewhere" "$session"
if PATH="$scratch/bin:$PATH" MOCK_TRACE="$scratch/trace" bash "$entrypoint" apply --root "$root" --inputs "$scratch/ops-access-inputs.json" --plan-file "$plan" --expected-sha "$sha" --session-handoff "$session" >/dev/null 2>&1; then
  printf 'symlink session handoff unexpectedly passed\n' >&2; exit 1
fi
[ "$(wc -l < "$scratch/trace" | tr -d ' ')" = "$before_handoff" ] || { printf 'symlink session handoff reached Terraform\n' >&2; exit 1; }
rm -f "$session"; mkdir "$session"
if PATH="$scratch/bin:$PATH" MOCK_TRACE="$scratch/trace" bash "$entrypoint" apply --root "$root" --inputs "$scratch/ops-access-inputs.json" --plan-file "$plan" --expected-sha "$sha" --session-handoff "$session" >/dev/null 2>&1; then
  printf 'directory session handoff unexpectedly passed\n' >&2; exit 1
fi
[ "$(wc -l < "$scratch/trace" | tr -d ' ')" = "$before_handoff" ] || { printf 'directory session handoff reached Terraform\n' >&2; exit 1; }
rm -rf "$session"; mkdir "$scratch/handoff-directory"; ln -s "$scratch/handoff-directory" "$session"
if PATH="$scratch/bin:$PATH" MOCK_TRACE="$scratch/trace" bash "$entrypoint" apply --root "$root" --inputs "$scratch/ops-access-inputs.json" --plan-file "$plan" --expected-sha "$sha" --session-handoff "$session" >/dev/null 2>&1; then
  printf 'symlink-to-directory session handoff unexpectedly passed\n' >&2; exit 1
fi
[ "$(wc -l < "$scratch/trace" | tr -d ' ')" = "$before_handoff" ] || { printf 'symlink-to-directory session handoff reached Terraform\n' >&2; exit 1; }
rm -f "$session"
if PATH="$scratch/bin:$PATH" MOCK_TRACE="$scratch/trace" MOCK_RACE_MODE=directory MOCK_RACE_SESSION_HANDOFF="$session" \
  bash "$entrypoint" apply --root "$scratch/mock-root" --inputs "$scratch/ops-access-inputs.json" --plan-file "$plan" --expected-sha "$sha" --session-handoff "$session" >"$scratch/race-directory.log" 2>&1; then
  printf 'raced directory session handoff unexpectedly passed\n' >&2; exit 1
fi
[ -d "$session" ] && [ ! -e "$session/.node-operator-session-handoff" ] || { cat "$scratch/race-directory.log" >&2; printf 'raced directory handoff was not preserved\n' >&2; exit 1; }
rm -rf "$session"; mkdir "$scratch/raced-handoff-directory"
if PATH="$scratch/bin:$PATH" MOCK_TRACE="$scratch/trace" MOCK_RACE_MODE=symlink-directory MOCK_RACE_SESSION_HANDOFF="$session" MOCK_RACE_DIRECTORY="$scratch/raced-handoff-directory" \
  bash "$entrypoint" apply --root "$scratch/mock-root" --inputs "$scratch/ops-access-inputs.json" --plan-file "$plan" --expected-sha "$sha" --session-handoff "$session" >/dev/null 2>&1; then
  printf 'raced symlink-to-directory session handoff unexpectedly passed\n' >&2; exit 1
fi
[ -L "$session" ] && [ ! -e "$scratch/raced-handoff-directory/.node-operator-session-handoff" ] || { printf 'raced symlink-to-directory handoff was not preserved\n' >&2; exit 1; }
rm -f "$session"; victim="$scratch/private/handoff-victim"; printf 'victim\n' > "$victim"; chmod 644 "$victim"
if ! PATH="$scratch/bin:$PATH" MOCK_TRACE="$scratch/trace" OPS_REAL_PYTHON="$real_python" MOCK_POST_LINK_SWAP=true MOCK_POST_LINK_TARGET="$session" MOCK_POST_LINK_VICTIM="$victim" \
  bash "$entrypoint" apply --root "$scratch/mock-root" --inputs "$scratch/ops-access-inputs.json" --plan-file "$plan" --expected-sha "$sha" --session-handoff "$session" >/dev/null 2>&1; then
  printf 'post-link replacement fixture unexpectedly failed\n' >&2; exit 1
fi
[ -L "$session" ] || { printf 'post-link replacement did not replace handoff\n' >&2; exit 1; }
if ! victim_mode="$(stat -c '%a' "$victim" 2>/dev/null)"; then victim_mode="$(stat -f '%OLp' "$victim")"; fi
[ "$victim_mode" = 644 ] || { printf 'post-link replacement chmodded victim\n' >&2; exit 1; }
if PATH="$scratch/bin:$PATH" MOCK_TRACE="$scratch/trace" bash "$entrypoint" "${common[@]}" \
  --backend-profile '../unsafe' --expected-backend-principal-arn arn:aws:iam::106760547719:role/NodeOperatorTerraformApply \
  --provider-profile provider-read --expected-provider-principal-arn arn:aws:iam::106760547719:role/NodeOperatorProviderRead >/dev/null 2>&1; then
  printf 'unsafe profile name unexpectedly passed\n' >&2
  exit 1
fi

if PATH="$scratch/bin:$PATH" MOCK_TRACE="$scratch/trace" bash "$entrypoint" destroy --root "$root" \
  --inputs "$scratch/ops-access-inputs.json" --config "$scratch/config.tfvars" --plan-file "$scratch/private/unused-plan" >/dev/null 2>&1; then
  printf 'mixed direct and generated ops inputs unexpectedly passed\n' >&2
  exit 1
fi
if PATH="$scratch/bin:$PATH" MOCK_TRACE="$scratch/trace" bash "$entrypoint" destroy --root "$root" \
  --inputs "$scratch/ops-access-inputs.json" --plan-file "$scratch/private/unused-plan" --session-handoff "$scratch/session.json" >/dev/null 2>&1; then
  printf 'session handoff outside generated apply unexpectedly passed\n' >&2
  exit 1
fi

printf 'PASS ops-access Terraform backend and provider credentials are separately verified and fail closed.\n'
