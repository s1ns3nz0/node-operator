# Cost-optimized Hoodi operation

The private EKS API remains private. Compute is split into three managed node
groups, each with `min=0` and `desired=0` in Terraform:

| Pool | Instance type | Maximum | Purpose |
| --- | --- | --- | --- |
| `node-operator-managed` | `m7i.2xlarge` | 3 | Kubernetes system add-ons and control-plane-adjacent workloads |
| `node-operator-consensus` | `m7i.2xlarge` | 1 | Prysm Hoodi consensus client |
| `node-operator-execution` | `m7i.4xlarge` | 1 | Nethermind Hoodi execution client |

The system pool must be ready before either client pool. Scaling all pools to
zero stops EC2 compute charges, but EBS PVC capacity is deliberately retained
and continues to incur storage charges.

## Apply prerequisite

The Terraform apply input must set `hoodi_nat_gateway_id` to the already
approved NAT gateway that is the default route for both private worker
subnets. Terraform only reads that gateway; it does not create or alter public
networking. The dedicated Hoodi security group permits only TCP/443,
TCP/UDP 30303, and TCP/UDP 13000 beyond the VPC. Flow Logs remain enabled.

## Start a Hoodi session

Run these commands with the approved AWS identity. Wait for the system pool
before scaling workload pools; this lets CoreDNS, VPC CNI, and EBS CSI recover
first.

```bash
aws eks update-nodegroup-config --region ap-northeast-2 --cluster-name node-operator \
  --nodegroup-name node-operator-managed \
  --scaling-config minSize=1,desiredSize=1,maxSize=3

kubectl wait --for=condition=Ready nodes --all --timeout=15m

aws eks update-nodegroup-config --region ap-northeast-2 --cluster-name node-operator \
  --nodegroup-name node-operator-consensus \
  --scaling-config minSize=0,desiredSize=1,maxSize=1
aws eks update-nodegroup-config --region ap-northeast-2 --cluster-name node-operator \
  --nodegroup-name node-operator-execution \
  --scaling-config minSize=0,desiredSize=1,maxSize=1
```

Confirm node labels before applying the two StatefulSets:

```bash
kubectl get nodes -L node-operator.io/network,node-operator.io/role
kubectl get pods -n kube-system
```

## Stop a Hoodi session

Scale clients down first and wait for their StatefulSets to terminate. This
does not delete retained EBS volumes. Then scale the system pool to zero.

```bash
kubectl scale statefulset -n node-operator nethermind-execution prysm-beacon --replicas=0
kubectl wait --for=delete pod -n node-operator -l app.kubernetes.io/part-of=hoodi-node --timeout=15m

aws eks update-nodegroup-config --region ap-northeast-2 --cluster-name node-operator \
  --nodegroup-name node-operator-consensus \
  --scaling-config minSize=0,desiredSize=0,maxSize=1
aws eks update-nodegroup-config --region ap-northeast-2 --cluster-name node-operator \
  --nodegroup-name node-operator-execution \
  --scaling-config minSize=0,desiredSize=0,maxSize=1
aws eks update-nodegroup-config --region ap-northeast-2 --cluster-name node-operator \
  --nodegroup-name node-operator-managed \
  --scaling-config minSize=0,desiredSize=0,maxSize=3
```

Terraform ignores operational `desiredSize` drift so an intervening plan does
not unexpectedly stop an active session. It still owns the zero minimum and
the maximum bounds.
