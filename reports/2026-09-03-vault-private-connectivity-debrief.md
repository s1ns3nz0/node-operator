# Clean-room debrief: Vault private connectivity

## Scope reviewed

This debrief was prepared from the completed task bundle
`plans/2026-09-03-vault-private-connectivity/`, the implementation diff
`fd5c4a9..c2ea65e`, and the recorded check outcomes only. It is an independent
summary of the repository change, not evidence of a live environment.

## Documented guardrails

The change adds a non-secret, fail-closed operating contract for the approved
self-hosted release runner and CodeBuild paths to Vault. It fixes the
release-facing name to `vault.node-operator.internal`, limits the API path to
HTTPS/TCP 8200, requires a private endpoint or internal gateway in front of
the existing ClusterIP service, and prohibits public DNS, raw-IP access,
alternate names, HTTP, certificate bypass, and public exposure.

The contract requires split-horizon private DNS without public fallback, a
private-CA certificate with the expected SNI/SAN, and certificate rotation and
expiration controls. It separately constrains runner and CodeBuild routes,
security-group rules, and network policies to their least-privilege purposes;
it prohibits all-address Internet egress, NAT/public fallback, and exposure of
Raft TCP 8201. Network admission remains defense in depth rather than Vault
authorization.

Before a release can proceed, the documented process requires retained,
non-secret DNS, TLS, route, authorization, deny-path, and audit-correlation
probe evidence. Missing or failed evidence is specified to stop the release.

## Validation evidence reviewed

The bundle records these passed checks:

- Vault private connectivity contract: `npm run test:vault-private-connectivity-contract`
- Vault GitOps contract: `npm run test:vault-gitops-contract`
- Vault private runner contract: `npm run test:vault-private-release-runner-contract`
- Harness task graph validation: `npm run harness:check`
- Whitespace validation: `git diff --check`

The targeted test is a structural repository check: it confirms the presence
of required control language and rejects selected unsafe patterns. It does not
test a cloud network or a running Vault endpoint.

## Not performed or evidenced

No cloud deployment was performed. In particular, this change did not create
or validate a private endpoint or gateway, DNS zone/record, TLS certificate,
route, load balancer, security group, NetworkPolicy, or any other cloud or
Kubernetes runtime resource.

No DNS or TLS provisioning occurred. No certificate issuance, installation,
rotation, expiration monitoring, or revocation validation was performed.

No live probes were run from the release runner, CodeBuild, public DNS, or any
other source. Therefore there is no live evidence of private DNS resolution,
TCP reachability or denial, TLS chain/SNI validation, Vault authorization,
audit correlation, or Raft isolation.

The documented controls are suitable prerequisites for separately authorized
rollout work. They are not authorization for that work, and they do not prove
the intended runtime configuration exists.
