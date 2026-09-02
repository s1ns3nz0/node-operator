# Clean-room debrief: local workload-specific egress validation

## Outcome

The supplied local Cilium execution evidence supports a **passed** result for
the narrow workload-specific controlled-egress policy check.  In the Ready
`kind-node-operator-cilium` cluster, disposable probes bearing the exact Prysm
and Nethermind workload labels demonstrated the expected distinct allowlists
and rejected the supplied wrong-port and external-destination cases.

## Scope reviewed

I independently reviewed the `2026-09-02-local-workload-egress` task bundle,
the working-tree diff from `dd89c97`, and the supplied validation results. The
change adds local-only, digest-pinned gateway fixtures and restricted probes,
plus `npm run test:local-workload-egress`.  The test applies the base, Prysm,
and Nethermind NetworkPolicies only to the explicitly named local Cilium
context; it contains no client-node or AWS action.

## Observed evidence

- `npm run test:local-workload-egress` passed while
  `kind-node-operator-cilium` was Ready.
- The Prysm-labelled probe resolved cluster DNS and was allowed TCP and UDP to
  the labelled P2P fixture on port 13000, as well as TCP to the labelled HTTPS
  fixture on port 443.  Its TCP connection to port 30303 and its TCP connection
  to external `1.1.1.1:443` were denied.
- The Nethermind-labelled probe resolved cluster DNS and was allowed TCP and
  UDP to the labelled P2P fixture on port 30303, as well as TCP to the labelled
  HTTPS fixture on port 443.  Its TCP connection to port 13000 and its TCP
  connection to external `1.1.1.1:443` were denied.
- The fixtures and probes use pinned image digests and restrictive pod/container
  settings, including non-root execution, runtime-default seccomp, dropped
  capabilities, read-only root filesystems, and no service-account-token mount
  on the probes.
- The test's exit handler initiated deletion of the `node-operator` and
  `node-operator-gateway` namespaces.  Final cleanup confirmation remains an
  integration responsibility.

## What this establishes

This is local Cilium dataplane evidence that the Prysm and Nethermind policy
selectors differentiate the workload labels and enforce their respective DNS,
controlled P2P port/protocol, and controlled HTTPS-port paths.  The tested
negative paths also show that the supplied wrong P2P port and an external TCP
443 destination were not permitted for either probe.

## Limits and non-findings

The P2P and HTTPS endpoints are local echo fixtures, not a real egress gateway,
TLS endpoint, or Ethereum peer.  Accordingly, this does not validate gateway
routing, TLS negotiation or certificate handling, peer discovery, or client
runtime behavior.

This result is limited to the local Kind/Cilium environment.  It does not
validate EKS or AWS networking, identity, security groups, routing, storage,
or any cloud integration.  No Prysm or Nethermind client node was started, and
there is no evidence here of image/runtime operation, Hoodi synchronization,
or real external connectivity.

Record the task as **passed for the stated local controlled-egress policy
probes**, with fixture cleanup still to be independently confirmed during
integration and all real gateway, TLS, peer, client-runtime, EKS, and AWS
behavior remaining unvalidated.
