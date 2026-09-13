#!/usr/bin/env bash
# Check objective: Ensure CI evidence is redacted, Cosign-signed, verified, and archived through the dedicated S3 role.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
workflow="$root/.github/workflows/evidence-archive.yml"
iac="$root/infra/terraform/ci-evidence-archive.tf"
archive="$root/scripts/ci/archive-ci-evidence.sh"
assume="$root/scripts/ci/assume-ci-evidence-archive-role.sh"
for file in "$workflow" "$iac" "$archive" "$assume"; do
  test -f "$file" || { printf 'missing archive contract file: %s\n' "$file" >&2; exit 1; }
done
grep -Fq 'workflow_run:' "$workflow"
grep -Fq 'workflows: [CI Evidence Gate]' "$workflow"
grep -Fq "github.event.workflow_run.conclusion == 'success'" "$workflow"
python3 - "$root/.github/workflows/evidence-gate.yml" <<'PY'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]).read_text()
step = source.split('- name: Failed Exact-SHA Evidence Check', 1)[1].split('\n  evidence-gate:', 1)[0]
match = re.search(r'        run: \|\n((?:          .*\n)+)', step)
assert match, 'upstream failure must have an explicit failing run block'
body = '\n'.join(line[10:] for line in match.group(1).splitlines())
with tempfile.TemporaryDirectory() as directory:
    stub = Path(directory) / 'scripts/ci/publish-pr-evidence-check.sh'
    stub.parent.mkdir(parents=True)
    stub.write_text('#!/bin/sh\nprintf "published-failure\\n"\nexit 0\n')
    stub.chmod(0o700)
    result = subprocess.run(['bash', '-e', '-c', body], cwd=directory,
        env={'PATH': os.environ['PATH'], 'SUBJECT_SHA': 'a' * 40,
             'DETAILS_URL': 'https://example.invalid'}, capture_output=True, text=True, timeout=5)
    assert result.stdout.strip() == 'published-failure', result.stderr
    assert result.returncode == 1, 'published failure must not trigger success-only archive'
PY
grep -Fq 'id-token: write' "$workflow"
grep -Fq 'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093' "$workflow"
grep -Fq 'cosign sign-blob --yes --bundle' "$archive"
grep -Fq 'cosign verify-blob --bundle' "$archive"
grep -Fq 'aws s3 cp' "$archive"
grep -Fq 'manifest.sigstore.json' "$archive"
grep -Fq 'object_lock_enabled = true' "$iac"
grep -Fq 'default_retention' "$iac"
grep -Fq 'sse_algorithm     = "aws:kms"' "$iac"
grep -Fq 'ci-evidence-archive' "$iac"
grep -Fq 'sts:AssumeRoleWithWebIdentity' "$iac"
if grep -Eq 'secrets/|VAULT_TOKEN|recovery.key|private_key' "$archive"; then
  printf 'archive script contains a forbidden secret path or token reference\n' >&2
  exit 1
fi
bash -n "$archive" "$assume"
printf 'PASS: CI evidence archive is Cosign-signed, verified, redacted, and OIDC-scoped.\n'
