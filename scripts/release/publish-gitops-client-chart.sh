#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() { printf '%s\n' "usage: ${0##*/} --handoff /absolute/gitops-publisher-handoff.json --output /absolute/new-promotion-handoff.json"; exit 64; }
handoff=''; output=''
while [ "$#" -gt 0 ]; do case "$1" in --handoff) handoff="${2:-}"; shift 2;; --output) output="${2:-}"; shift 2;; *) usage;; esac; done
case "$handoff:$output" in /*:/*) ;; *) usage;; esac
[ -f "$handoff" ] && [ ! -L "$handoff" ] || { printf '%s\n' 'handoff must be a regular file' >&2; exit 65; }
[ ! -e "$output" ] && [ ! -L "$output" ] || { printf '%s\n' 'output must not already exist' >&2; exit 65; }
for command in jq gh unzip; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 127; }; done
github() { env -u GITHUB_TOKEN gh "$@"; }
repository="$(jq -er '.schema_version == "v1" and .gitops_repository | select(test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"))' "$handoff")" || exit 65
account="$(jq -er '.aws_account_id | select(test("^[0-9]{12}$"))' "$handoff")" || exit 65

github workflow run publish-oci.yml --repo "$repository" --ref main
run_id="$(github run list --repo "$repository" --workflow publish-oci.yml --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
[[ "$run_id" =~ ^[1-9][0-9]*$ ]] || { printf '%s\n' 'unable to resolve publisher run' >&2; exit 70; }
github run watch "$run_id" --repo "$repository" --exit-status
artifact_id="$(github api "repos/$repository/actions/runs/$run_id/artifacts?per_page=100" --jq '.artifacts[] | select(.name | startswith("gitops-chart-evidence-")) | select(.expired == false) | .id' | head -1)"
[[ "$artifact_id" =~ ^[1-9][0-9]*$ ]] || { printf '%s\n' 'publisher evidence artifact is unavailable' >&2; exit 70; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
github api "repos/$repository/actions/artifacts/$artifact_id/zip" > "$tmp/evidence.zip"
subject="$(unzip -Z1 "$tmp/evidence.zip" | awk -F/ '$NF == "gitops-chart-subject.json" {print; exit}')"
[ -n "$subject" ] || { printf '%s\n' 'publisher evidence has no chart subject' >&2; exit 70; }
unzip -p "$tmp/evidence.zip" "$subject" > "$tmp/subject.json"
jq -e --arg account "$account" '.schema_version == "v1" and (.oci_digest | test("^sha256:[a-f0-9]{64}$")) and (.chart_version | test("^0\\.1\\.[0-9]+$"))' "$tmp/subject.json" >/dev/null || { printf '%s\n' 'publisher evidence has invalid chart identity' >&2; exit 70; }
jq --arg repository "$repository" --arg account "$account" '{schema_version:"v1",gitops_repository:$repository,aws_account_id:$account,chart_version:.chart_version,chart_oci_digest:.oci_digest,chart_archive_digest:.chart_archive_digest}' "$tmp/subject.json" > "$output"
chmod 600 "$output"
printf 'PASS: immutable GitOps chart promotion handoff saved to %s\n' "$output"
