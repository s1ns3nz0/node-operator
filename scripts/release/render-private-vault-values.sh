#!/usr/bin/env bash
set -euo pipefail
umask 077
usage() { printf '%s\n' 'usage: render-private-vault-values.sh --template FILE --output ABSOLUTE_FILE --aws-account-id ID --aws-region REGION --unseal-key-arn ARN --server-image ECR@sha256:DIGEST --agent-image ECR@sha256:DIGEST --injector-image ECR@sha256:DIGEST --audit-relay-image ECR@sha256:DIGEST' >&2; exit 64; }
template='' output='' account='' region='' kms='' server='' agent='' injector='' relay=''
while [ "$#" -gt 0 ]; do case "$1" in
 --template) template=${2:-}; shift 2;; --output) output=${2:-}; shift 2;; --aws-account-id) account=${2:-}; shift 2;; --aws-region) region=${2:-}; shift 2;; --unseal-key-arn) kms=${2:-}; shift 2;; --server-image) server=${2:-}; shift 2;; --agent-image) agent=${2:-}; shift 2;; --injector-image) injector=${2:-}; shift 2;; --audit-relay-image) relay=${2:-}; shift 2;; *) usage;; esac; done
[[ $account =~ ^[0-9]{12}$ ]] && [[ $region =~ ^ap-northeast-(1|2)$ ]] || usage
[[ $kms =~ ^arn:aws:kms:$region:$account:key/[A-Za-z0-9-]+$ ]] || usage
case "$output" in /*) ;; *) usage;; esac
[ -f "$template" ] && [ ! -L "$template" ] && [ ! -e "$output" ] && [ ! -L "$output" ] || { printf '%s\n' 'template or output path is unsafe' >&2; exit 65; }
parent=$(dirname "$output"); [ -d "$parent" ] && [ ! -L "$parent" ] || { printf '%s\n' 'output parent is unsafe' >&2; exit 65; }
parent_mode=$(stat -c '%a' "$parent" 2>/dev/null) || parent_mode=$(stat -f '%OLp' "$parent")
case "$parent_mode" in 700) ;; *) printf '%s\n' 'output parent must be private' >&2; exit 65;; esac
image_parts() { local image=$1 prefix repo digest; prefix="$account.dkr.ecr.$region.amazonaws.com/"; [[ $image =~ ^$account\.dkr\.ecr\.$region\.amazonaws\.com/[a-z0-9][a-z0-9._/-]*@sha256:[a-f0-9]{64}$ ]] || return 1; repo=${image#"$prefix"}; repo=${repo%@sha256:*}; digest=${image##*@sha256:}; printf '%s\n%s@sha256:%s\n' "$prefix$repo" "$digest" "$digest"; }
read_image() { local rendered; rendered=$(image_parts "$1") || usage; REPO=${rendered%%$'\n'*}; TAG=${rendered#*$'\n'}; [ "$REPO" != "$rendered" ] && [ -n "$TAG" ] || usage; }
read_image "$server"; server_repo=$REPO server_tag=$TAG
read_image "$agent"; agent_repo=$REPO agent_tag=$TAG
read_image "$injector"; injector_repo=$REPO injector_tag=$TAG
read_image "$relay"; relay_full="$relay"
stage=$(mktemp "$parent/.vault-values.XXXXXX") || exit 1
cleanup(){ rm -f "$stage"; }; trap cleanup EXIT
sed -e "s|__VAULT_AWS_REGION__|$region|g" -e "s|__VAULT_UNSEAL_KEY_ARN__|$kms|g" -e "s|__VAULT_SERVER_REPOSITORY__|$server_repo|g" -e "s|__VAULT_SERVER_TAG__|$server_tag|g" -e "s|__VAULT_AGENT_REPOSITORY__|$agent_repo|g" -e "s|__VAULT_AGENT_TAG__|$agent_tag|g" -e "s|__VAULT_INJECTOR_REPOSITORY__|$injector_repo|g" -e "s|__VAULT_INJECTOR_TAG__|$injector_tag|g" -e "s|__VAULT_AUDIT_RELAY_IMAGE__|$relay_full|g" "$template" > "$stage"
grep -q '__VAULT_' "$stage" && { printf '%s\n' 'template contains an unresolved Vault token' >&2; exit 65; }
grep -Eq '106760547719|REPLACE_WITH_' "$stage" && { printf '%s\n' 'template contains historical deployment data' >&2; exit 65; }
chmod 600 "$stage"
set -C
if ! cat "$stage" > "$output" 2>/dev/null; then printf '%s\n' 'refusing to overwrite output' >&2; exit 65; fi
set +C
printf 'PASS rendered non-secret private Vault values at %s\n' "$output"
