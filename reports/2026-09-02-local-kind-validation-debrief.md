# Clean-room debrief: local Kind validation

## Outcome

The local-only overlay is suitable for its narrow purpose: it rendered the
production-shaped Prysm and Nethermind workload objects with both StatefulSets
scaled to zero, and a disposable local Kind v1.35 cluster admitted the rendered
resources.  The evidence supports static/rendering and Kubernetes API object
validation only.  It is not evidence that the workloads can run on EKS or that
their runtime security and storage assumptions hold in AWS.

## Scope reviewed

I independently reviewed the task bundle, the working-tree changes relative to
base `3729ede`, and the stated validation results.  The added local overlay
copies the base, Prysm, and Nethermind resources, then patches only
`spec.replicas` to `0` for `prysm-beacon` and `nethermind-execution`.  The
original pod templates, pinned images, storage classes, selectors, security
contexts, RBAC, and NetworkPolicies remain represented in the rendered output.

## Observed evidence

- `npm run test:local-kind-overlay` passed.  Its renderer assertions confirm
  both StatefulSets render with zero replicas and retain their pinned client
  images.
- On Docker Desktop, a disposable Kind v1.35 cluster accepted all rendered
  resources with `kubectl --context kind-node-operator-local apply
  --dry-run=server -f /tmp/node-operator-local-kind.yaml`, after the actual
  `node-operator` Namespace had been created.
- A real local apply created the zero-replica StatefulSets, ServiceAccounts,
  RBAC objects, and NetworkPolicies.
- Authorization behavior matched the reviewed Role: `node-workload` can `get`
  ConfigMaps and cannot `list` ConfigMaps.
- No blockchain client image was started and no Hoodi synchronization ran.

## What this establishes

The overlay is a controlled local admission/object-validation mechanism: the
API server accepted the rendered Kubernetes resource schemas and references in
this Kind environment, the zero-replica patches prevent client Pods from being
created, and the tested RBAC permission boundary behaves as declared.

## Limits and non-findings

The successful local admission and object checks do not validate any of the
following:

- AWS or EKS control-plane, identity, or node behavior.
- EBS CSI provisioning, gp3 capacity/IOPS/throughput, KMS aliases or key
  authorization, or durable volume mounting.
- Scheduling against the required AWS node labels and Seoul availability zones,
  including the workload resource requests and cross-node anti-affinity in a
  multi-node topology.
- Actual NetworkPolicy enforcement or end-to-end DNS, peer, service, and egress
  connectivity.  Object acceptance is not dataplane enforcement.
- Client image pull/startup, probes, Hoodi synchronization, or client runtime
  behavior.

Accordingly, this task should be recorded as **passed for local static,
admission, object, and limited RBAC validation**, with the listed AWS, runtime,
network-enforcement, and multi-node concerns remaining unvalidated.
