#!/usr/bin/env bash
set -euo pipefail

# The adapter never downloads tools implicitly. This explicit bootstrap writes
# only to the caller-selected local tools directory.
destination="${1:-${CI_TOOL_BIN:-$PWD/.ci-tools/bin}}"
platform="$(uname -s)_$(uname -m)"

case "$platform" in
  Darwin_arm64)
    opa_url="https://github.com/open-policy-agent/opa/releases/download/v1.17.0/opa_darwin_arm64_static"
    opa_sha256="7d7debaf10bba97d32b7e67b7f8ce128c92e911b82e3c6cec24b95c34f8a5003"
    conftest_url="https://github.com/open-policy-agent/conftest/releases/download/v0.69.0/conftest_0.69.0_Darwin_arm64.tar.gz"
    conftest_sha256="78302d045f0ec52e9786a06c6c621ac4516b4c5dd1e54efc8050c86c29b964d9"
    shellcheck_url="https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.darwin.aarch64.tar.xz"
    shellcheck_sha256="bbd2f14826328eee7679da7221f2bc3afb011f6a928b848c80c321f6046ddf81"
    shellcheck_member="shellcheck-v0.10.0/shellcheck"
    ;;
  Linux_x86_64)
    opa_url="https://github.com/open-policy-agent/opa/releases/download/v1.17.0/opa_linux_amd64_static"
    opa_sha256="e83da46804832578e9d9e1733dffbe4d3b5f8cc9c26eb124da9ceea4abfe189f"
    conftest_url="https://github.com/open-policy-agent/conftest/releases/download/v0.69.0/conftest_0.69.0_Linux_x86_64.tar.gz"
    conftest_sha256="96fc2fbf11f0afde51256647127e6f00a64ce839a4d9a0a1aef2426c0e6f4b3f"
    shellcheck_url="https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.linux.x86_64.tar.xz"
    shellcheck_sha256="6c881ab0698e4e6ea235245f22832860544f17ba386442fe7e9d629f8cbedf87"
    shellcheck_member="shellcheck-v0.10.0/shellcheck"
    ;;
  *) printf 'unsupported policy-tool platform: %s\n' "$platform" >&2; exit 64 ;;
esac

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$destination"

download_and_verify() {
  local url="$1" expected_sha256="$2" output="$3"
  curl --fail --silent --show-error --location --output "$output" "$url"
  printf '%s  %s\n' "$expected_sha256" "$output" | shasum -a 256 --check --status
}

download_and_verify "$opa_url" "$opa_sha256" "$temporary_directory/opa"
install -m 0755 "$temporary_directory/opa" "$destination/opa"
download_and_verify "$conftest_url" "$conftest_sha256" "$temporary_directory/conftest.tar.gz"
tar -xzf "$temporary_directory/conftest.tar.gz" -C "$destination" conftest
chmod 0755 "$destination/conftest"
download_and_verify "$shellcheck_url" "$shellcheck_sha256" "$temporary_directory/shellcheck.tar.xz"
tar -xJf "$temporary_directory/shellcheck.tar.xz" -C "$temporary_directory" "$shellcheck_member"
install -m 0755 "$temporary_directory/$shellcheck_member" "$destination/shellcheck"

if [ -n "${GITHUB_PATH:-}" ]; then printf '%s\n' "$destination" >> "$GITHUB_PATH"; fi
printf 'Installed pinned OPA 1.17.0, Conftest 0.69.0, and ShellCheck 0.10.0 in %s\n' "$destination"
