# Clean-room debrief: operator handoff

## Scope

This independent, read-only review covered the untracked task bundle in
`plans/2026-09-05-operator-handoff/`, the handoff at
`docs/handoff/2026-09-05-operator-handoff.md`, its referenced checked-in
operations documents and scripts, and the working-tree status/diff including
untracked files. No cloud, cluster, registry, GitHub, or secret action was
taken. This reviewer created only this report.

## Observed evidence

- `git diff --check` completed without whitespace errors.
- `npm run harness:check` passed, reporting 68 task graphs checked.
- `npm run test:hoodi-session-contract`,
  `npm run test:argocd-ecr-oci-contract`, and
  `npm run test:validator-runtime-contract` passed.
- The handoff's Hoodi commands and prerequisite descriptions align with
  `scripts/ops/hoodi-session.sh`: start requires reviewed StatefulSets and
  only reads the metadata name of `engine-api-jwt`; it does not query or emit
  Secret data.
- The checked-in Argo Application is pinned to chart revision `0.1.6`, and
  the ECR credential refresher schedule is every six hours.
- Review of the task bundle and diff found no secret values, tokens, private
  keys, recovery materials, kubeconfigs, or raw logs.

## Finding

**Blocking — corrected after review:** The initial SSM fallback in the handoff
was not reproducible for an operator whose local terminal lacks private EKS
routing. It did not provide the parameterized Session Manager remote-host
forwarding procedure or a safe, disposable kubeconfig procedure. The temporary
host intentionally contains neither `kubectl` nor persistent credentials, so
the missing local tunnel procedure prevented the initial status commands from
reaching the private API.

The correction should document a parameterized
`AWS-StartPortForwardingSessionToRemoteHost` session to the EKS endpoint,
retain the original EKS hostname for TLS server-name validation, use a
disposable local kubeconfig/context pointing at the forwarded port, and
prohibit overwriting the normal context or using insecure TLS bypasses. Host
IDs, endpoint values, credentials, and session identifiers must remain out of
the handoff and evidence.

**Non-blocking:** The existing runbook's targeted Terraform destroy removes
the temporary EC2 instance but not necessarily all count-controlled support
resources while the enable flag remains true. The runbook should distinguish
that fast instance cleanup from a normal apply with the temporary-host flag
disabled, which removes the supporting resources.

## Resolution status

Sol added the parameterized `AWS-StartPortForwardingSessionToRemoteHost`
procedure, preserves the original EKS hostname through `tls-server-name`, uses
a disposable kubeconfig rather than the normal context, and prohibits insecure
TLS bypasses. The handoff also corrects the SSM cleanup guidance: normal
cleanup applies `enable_temporary_ssm_ops_host=false`, while instance-only
targeted destroy is documented as emergency cleanup. The post-review
structural and contract checks passed again. The blocking finding is resolved.
