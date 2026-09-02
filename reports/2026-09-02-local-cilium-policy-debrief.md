# Clean-room debrief: local Cilium policy validation

## Outcome

The local Cilium policy lab passed its narrow dataplane check.  In the
separate `node-operator-cilium` Kind cluster, the disposable restricted probe
could resolve `kubernetes.default.svc.cluster.local` but could not open TCP to
`1.1.1.1:443`.  This is evidence that Cilium enforced the repository's shared
default-deny plus DNS-only egress policies for that probe in that local
environment.

## Scope reviewed

I independently reviewed the `2026-09-02-local-cilium-policy` task bundle,
the working-tree changes based on `a417e97`, and the supplied execution
evidence.  The change adds an isolated Kind configuration with the default CNI
disabled, a digest-pinned and restricted BusyBox probe, and a bounded script
that applies `deploy/base/namespace.yaml` and
`deploy/base/network-policies.yaml` to the explicitly named local context.

The reviewed configuration defines one control-plane and three worker nodes.
The supplied evidence records installation of the official Cilium OCI chart
version `1.20.1` at digest
`sha256:906ce40d35daad838d12add8a5ba7033e767767f51799a93c7eace2cec9cdc05`;
all four nodes and the Cilium, Cilium Envoy, and Cilium Operator components
were Ready before the probe ran.

## Observed evidence

- The test targets only `kind-node-operator-cilium`; it stops if that local
  context is unavailable.
- It applies the namespace, the namespace-wide `default-deny-ingress-egress`
  policy, and the namespace-wide `allow-dns` policy, then creates the
  `local-policy-probe` Pod.
- The probe uses a pinned BusyBox digest, disables service-account-token
  automounting, runs as a non-root numeric user, drops all Linux capabilities,
  uses the runtime-default seccomp profile, and has a read-only root
  filesystem.
- After readiness, DNS lookup of
  `kubernetes.default.svc.cluster.local` succeeded.  A three-second TCP probe
  to `1.1.1.1:443` failed, which is the expected result under these two base
  policies.
- The script's exit trap deletes the probe.  Supplied evidence states that the
  probe was deleted after the test.
- No blockchain-client workload was run, no Hoodi synchronization occurred,
  and the task did not access AWS.

## What this establishes

This validates actual NetworkPolicy dataplane behavior for the common
DNS-only/default-deny boundary, using Cilium in the stated disposable Kind
topology.  It closes the gap left by the earlier local Kind admission check,
which could establish that NetworkPolicy objects were accepted but not that a
dataplane enforced them.

## Limits and non-findings

This result is deliberately Cilium-specific and local.  It does not establish
behavior for EKS or the AWS VPC CNI, including any EKS control-plane, managed
node, identity, routing, security-group, or AWS-network integration behavior.

It also does not validate EBS CSI provisioning, gp3 sizing, KMS authorization,
storage lifecycle, Pod Identity/IAM permissions, or AWS availability-zone and
node-label scheduling assumptions.  The tested policies were only the shared
base policies.  The Prysm and Nethermind workload-specific DNS and
controlled-egress policies, their labelled egress-gateway prerequisites, and
all client runtime connectivity remain untested.  No conclusion should be
drawn about client startup, image execution, peer discovery, HTTPS access via
a gateway, synchronization, or persistence.

Accordingly, record this task as **passed for local Cilium enforcement of the
base DNS/default-deny policy boundary**, with EKS/AWS, storage/IAM, and
workload-specific policy behavior remaining unvalidated.
