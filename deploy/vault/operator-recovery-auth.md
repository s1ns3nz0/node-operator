# Operator recovery authentication

Status: exact-user IAM prerequisite applied on2026-09-09; the operator auth
mount is not yet configured in the live Vault. Complete the runtime and user
login checks below before upgrading Vault2.x.

For this existing deployment, retain
`vault_operator_user_arn=arn:aws:iam::106760547719:user/jsyang` in subsequent
reviewed Terraform inputs. Omitting it selects the disabled default and may
plan removal of the lookup policy. This is not permission to full-apply
incomplete reconstructed inputs.

Use a separate `operator-aws` auth mount, not the release-signing mount. The
`operator-recovery` role accepts only one explicitly supplied IAM user in this
deployment's account and resolves that user's immutable AWS unique ID. The
role issues five-minute tokens with a hard ten-minute maximum and no default
policy. Its policy permits root-ceremony endpoints and self-revocation only;
recovery shares are still necessary to generate root. AWS IAM authentication
is not proof of MFA. Keep AWS access and recovery shares separately protected.

Prerequisites, in order:

1. Review a targeted Terraform plan setting `vault_operator_user_arn` to the
   exact operator user. The only intended permission addition is
   `iam:GetUser` on that single ARN for the existing Vault Pod Identity role.
   The default empty variable makes no change. Do not use a full apply with
   incomplete reconstructed inputs. Apply and verify this scoped change first.
2. Confirm Vault can reach regional STS and IAM and use Pod Identity credentials.
   No static AWS keys belong in the Vault auth configuration. The wrapper's
   IAM simulation is a prerequisite check, not proof of network or SDK behavior.
3. Review and run the user-held recovery ceremony while Vault1.x still works.
   It must refuse existing mount/policy names instead of overwriting them.
   The wrapper verifies current AWS identity and permission before asking for
   shares, configures the new path, attempts actual AWS login, checks exact
   token policy/TTL and denied administrative capabilities, then revokes both
   temporary tokens. Neither token is stored by `vault login`.

After the reviewed code is available and prerequisites have passed:

```sh
bash scripts/ops/recover-and-configure-private-vault-operator-auth.sh \
  --principal-arn arn:aws:iam::106760547719:user/jsyang
```

Never paste a recovery share, root token or AWS key into a command argument,
Git, CI, Terraform variables or chat. A failed configuration can leave a
partially configured dedicated mount/policy: stop, inspect those exact targets
with an administrator, and review repair. Do not automatically delete a mount
or rerun through its existence guard. Successful configuration is not approval
for the server upgrade: repeatable fresh login, HA/KMS and audit compatibility
remain required. The current helper supports pathless IAM users only; support
for roles/SSO identities needs separately reviewed bindings.

The signed server-ID header is
`node-operator-vault-operator-106760547719-apne2`; regional STS is
`https://sts.ap-northeast-2.amazonaws.com`. These are public configuration, not
credentials. Unique-ID binding must not be disabled to work around missing
`iam:GetUser` permission.

References: [AWS authentication](https://developer.hashicorp.com/vault/docs/auth/aws)
and [AWS auth API](https://developer.hashicorp.com/vault/api-docs/auth/aws).
