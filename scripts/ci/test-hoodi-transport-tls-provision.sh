#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
helper="$root/scripts/ops/provision-hoodi-transport-tls.sh"
scratch="$(mktemp -d /private/tmp/hoodi-transport-tls-test.XXXXXX)"
cleanup() { rm -rf "$scratch"; }
trap cleanup EXIT
mkdir -p "$scratch/bin"

cat > "$scratch/bin/aws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'AWS must not be called by the offline transport TLS test' >&2
exit 97
EOF

cat > "$scratch/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_KUBECTL_CALLS"
kind=''; name=''
for ((i=1; i <= $#; i++)); do
  if [ "${!i}" = get ]; then
    next=$((i + 1)); kind="${!next}"; next=$((i + 2)); name="${!next}"
    if [[ " $* " == *' --ignore-not-found '* ]]; then
      if [ "${MOCK_EXISTING_KIND:-}" = "$kind" ]; then printf '%s/%s\n' "$kind" "$name"; fi
      exit 0
    fi
    case "$name" in
      validator-hoodi-test-001-signer-tls) keys='tls-password.txt,tls.p12,' ;;
      validator-hoodi-test-001-client-tls) keys='ca.crt,tls.crt,tls.key,' ;;
      validator-hoodi-test-001-known-clients) keys='known-clients,' ;;
      *) exit 44 ;;
    esac
    case "${MOCK_READBACK_MODE:-ok}" in
      ok) printf '%s|uid-%s|rv-1|%s' "$name" "$name" "$keys" ;;
      missing-key) printf '%s|uid-%s|rv-1|%s' "$name" "$name" "${keys%%,*}," ;;
      wrong-name) printf 'wrong-name|uid-%s|rv-1|%s' "$name" "$keys" ;;
      api-error) exit 45 ;;
      *) exit 46 ;;
    esac
    exit 0
  fi
done
if [[ " $* " == *' create '* ]]; then
  count=0
  [ ! -e "$MOCK_CREATE_COUNT" ] || read -r count < "$MOCK_CREATE_COUNT"
  count=$((count + 1)); printf '%s\n' "$count" > "$MOCK_CREATE_COUNT"
  if [ "${MOCK_FAIL_CREATE_NUMBER:-0}" -eq "$count" ]; then exit 42; fi
  if [[ " $* " == *' create configmap '* ]]; then
    found=false
    for argument in "$@"; do
      case "$argument" in
        --from-file=known-clients=*)
          found=true; path="${argument#--from-file=known-clients=}"
          grep -Eq '^validator-hoodi-test-001-client ([A-Fa-f0-9]{2}:){31}[A-Fa-f0-9]{2}$' "$path"
          printf '%s\n' 'known-clients-key-and-value-ok' >> "$MOCK_KUBECTL_CALLS"
          ;;
      esac
    done
    [ "$found" = true ] || exit 43
  fi
fi
exit 0
EOF
chmod 0700 "$scratch/bin/aws" "$scratch/bin/kubectl"

run_helper() {
  MOCK_KUBECTL_CALLS="$scratch/calls" \
  MOCK_CREATE_COUNT="$scratch/create-count" \
  PRIVATE_EKS_SESSION=1 \
  PATH="$scratch/bin:$PATH" \
    "$helper" "$@"
}

assert_no_private_stdout() {
  file="$1"
  if grep -Eq -- 'BEGIN (RSA )?PRIVATE KEY|BEGIN CERTIFICATE|([A-Fa-f0-9]{2}:){16}' "$file"; then
    printf '%s\n' 'transport private material or certificate fingerprint reached stdout' >&2
    exit 1
  fi
}

: > "$scratch/calls"
dry_output="$scratch/dry-ca.crt"
run_helper --validator-set hoodi-test-001 --public-ca-output "$dry_output" --dry-run > "$scratch/dry.stdout" 2> "$scratch/dry.stderr"
[ ! -e "$dry_output" ]
if grep -Eq ' create (secret|configmap) ' "$scratch/calls"; then exit 1; fi
grep -Fq 'no Kubernetes resources changed' "$scratch/dry.stdout"
assert_no_private_stdout "$scratch/dry.stdout"

: > "$scratch/calls"; rm -f "$scratch/create-count"
set +e
MOCK_EXISTING_KIND=secret run_helper --validator-set hoodi-test-001 --public-ca-output "$scratch/existing-ca.crt" > "$scratch/existing.stdout" 2> "$scratch/existing.stderr"
existing_rc=$?
set -e
[ "$existing_rc" -eq 65 ]
[ ! -e "$scratch/existing-ca.crt" ]
if grep -Eq ' create (secret|configmap) ' "$scratch/calls"; then exit 1; fi
grep -Fq 'Transport Secret already exists' "$scratch/existing.stderr"
assert_no_private_stdout "$scratch/existing.stdout"

: > "$scratch/calls"; rm -f "$scratch/create-count"
run_helper --validator-set hoodi-test-001 --public-ca-output "$scratch/success-ca.crt" > "$scratch/success.stdout" 2> "$scratch/success.stderr"
openssl x509 -in "$scratch/success-ca.crt" -noout >/dev/null
grep -Fq 'create secret generic validator-hoodi-test-001-signer-tls' "$scratch/calls"
grep -Fq -- '--from-file=tls.p12=' "$scratch/calls"
grep -Fq 'create secret generic validator-hoodi-test-001-client-tls' "$scratch/calls"
grep -Fq -- '--from-file=tls.crt=' "$scratch/calls"
grep -Fq -- '--from-file=tls.key=' "$scratch/calls"
grep -Fq -- '--from-file=ca.crt=' "$scratch/calls"
grep -Fq 'create configmap validator-hoodi-test-001-known-clients --from-file=known-clients=' "$scratch/calls"
grep -Fq 'known-clients-key-and-value-ok' "$scratch/calls"
assert_no_private_stdout "$scratch/success.stdout"

for readback_mode in missing-key wrong-name api-error; do
  : > "$scratch/calls"; rm -f "$scratch/create-count"
  set +e
  MOCK_READBACK_MODE="$readback_mode" run_helper --validator-set hoodi-test-001 --public-ca-output "$scratch/readback-$readback_mode-ca.crt" > "$scratch/readback-$readback_mode.stdout" 2> "$scratch/readback-$readback_mode.stderr"
  readback_rc=$?
  set -e
  [ "$readback_rc" -eq 70 ]
  grep -Fq 'CRITICAL: partial transport provisioning' "$scratch/readback-$readback_mode.stderr"
  if [ "$readback_mode" != api-error ]; then grep -Fq 'Transport resource inventory verification failed' "$scratch/readback-$readback_mode.stderr"; fi
  assert_no_private_stdout "$scratch/readback-$readback_mode.stdout"
done

: > "$scratch/calls"; rm -f "$scratch/create-count"
set +e
MOCK_FAIL_CREATE_NUMBER=2 run_helper --validator-set hoodi-test-001 --public-ca-output "$scratch/partial-ca.crt" > "$scratch/partial.stdout" 2> "$scratch/partial.stderr"
partial_rc=$?
set -e
[ "$partial_rc" -eq 70 ]
grep -Fq 'CRITICAL: partial transport provisioning' "$scratch/partial.stderr"
grep -Fq 'create secret generic validator-hoodi-test-001-signer-tls' "$scratch/calls"
grep -Fq 'create secret generic validator-hoodi-test-001-client-tls' "$scratch/calls"
if grep -Fq 'create configmap validator-hoodi-test-001-known-clients' "$scratch/calls"; then exit 1; fi
assert_no_private_stdout "$scratch/partial.stdout"

printf '%s\n' 'PASS: transport TLS provisioning is offline-tested, fail-closed, and does not print private material.'
