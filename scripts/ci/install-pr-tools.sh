#!/usr/bin/env bash
set -euo pipefail

# Install the exact CLI releases consumed by the T-8 collector. This command is
# intentionally separate from the workflow so its version boundary is reviewable.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"

require_command cargo
require_command go
require_command python3
require_command terraform

tool_directory="${1:-$PWD/.ci-tools/bin}"
mkdir -p "$tool_directory"
tool_root="${tool_directory%/bin}"
export GOBIN="$tool_directory"
export PATH="$tool_directory:$PATH"
[ -z "${GITHUB_PATH:-}" ] || printf '%s\n' "$tool_directory" >> "$GITHUB_PATH"

go install github.com/zricethezav/gitleaks/v8@v8.30.1
go install github.com/google/osv-scanner/v2/cmd/osv-scanner@v2.4.0
cargo install --root "$tool_root" --version 1.12.1 --locked zizmor
python3 -m pip install --ignore-installed --disable-pip-version-check --no-warn-script-location --prefix "$tool_root" 'semgrep==1.159.0' 'checkov==3.2.522'
export PATH="$tool_root/bin:$PATH"
[ -z "${GITHUB_PATH:-}" ] || printf '%s\n' "$tool_root/bin" >> "$GITHUB_PATH"

for command in gitleaks osv-scanner zizmor semgrep checkov terraform; do
  require_command "$command"
done
