#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
entrypoint="$root/scripts/release/node-operator-ops-access.sh"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/ops-access-release.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
bundle="$scratch/bundle"
mkdir -p "$bundle/infra" "$bundle/scripts/ci" "$scratch/bin"
cp -R "$root/infra/ops-access" "$bundle/infra/ops-access"
cp "$root/scripts/ci/check-ops-access-ssm-retention-plan.sh" "$bundle/scripts/ci/"
chmod +x "$bundle/scripts/ci/check-ops-access-ssm-retention-plan.sh"
: > "$scratch/config.tfvars"
: > "$scratch/backend.hcl"
printf 'invalid-plan\n' > "$scratch/plan"
printf '{}\n' > "$scratch/plan.json"
cat > "$scratch/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *' init '*) exit 0 ;;
  *' show -json '*) cat "$MOCK_PLAN_JSON" ;;
  *' apply '*) printf 'apply\n' >> "$MOCK_TRACE" ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$scratch/bin/terraform"
expected="$(shasum -a 256 "$scratch/plan" | awk '{print $1}')"
if PATH="$scratch/bin:$PATH" MOCK_PLAN_JSON="$scratch/plan.json" MOCK_TRACE="$scratch/trace" bash "$entrypoint" apply --root "$bundle" --config "$scratch/config.tfvars" --backend-config "$scratch/backend.hcl" --plan-file "$scratch/plan" --expected-sha "$expected" >/dev/null 2>&1; then
  printf 'invalid saved plan unexpectedly applied\n' >&2; exit 1
fi
test ! -e "$scratch/trace"
if PATH="$scratch/bin:$PATH" MOCK_PLAN_JSON="$scratch/plan.json" MOCK_TRACE="$scratch/trace" bash "$entrypoint" apply --root "$bundle" --config "$scratch/config.tfvars" --backend-config "$scratch/backend.hcl" --plan-file "$scratch/plan" --expected-sha 0000000000000000000000000000000000000000000000000000000000000000 >/dev/null 2>&1; then
  printf 'changed saved plan unexpectedly applied\n' >&2; exit 1
fi
test ! -e "$scratch/trace"
printf 'PASS ops-access wrapper rejects invalid or changed saved plans before apply.\n'
