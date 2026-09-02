# Local workload egress lab

Run this only after the Cilium lab is Ready in the
`kind-node-operator-cilium` context:

```sh
scripts/ci/test-local-workload-egress.sh
```

The test uses a separate namespace labelled as the controlled gateway and
small, digest-pinned non-root probe Pods labelled exactly like the Prysm and
Nethermind workloads. It proves the policy matrix below, then initiates
deletion of both test namespaces. Confirm completion with `kubectl get ns`.

| Probe | Allowed gateway paths | Denied paths |
| --- | --- | --- |
| Prysm | TCP/UDP 13000 and TCP 443 | TCP 30303 and external TCP 443 |
| Nethermind | TCP/UDP 30303 and TCP 443 | TCP 13000 and external TCP 443 |

The gateway is a local echo fixture, not a real egress gateway. This does not
test EKS/AWS networking, Cilium on EKS, peer discovery, the internet, TLS, or
either client runtime.
