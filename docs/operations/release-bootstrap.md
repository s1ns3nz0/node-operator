# Hoodi release bootstrap

The distributable Hoodi release is a deterministic, non-secret artifact. A
consumer verifies the extracted artifact before using its Terraform baseline:

```sh
tar -xf node-operator-release-bundle.tar -C release
release/source/scripts/release/node-operator-release.sh verify --bundle-root release
release/source/scripts/release/node-operator-release.sh bootstrap plan \
  --bundle-root release --config /controlled-input/hoodi.ap-northeast-2.tfvars
```

`bootstrap apply` uses the same verified input after the reviewed plan is
approved. AWS credentials and the configured encrypted Terraform backend must
come from the controlled execution environment. The release archive contains
neither credentials nor backend state.

The baseline creates private infrastructure and the GitOps artifact
foundation; it does not treat an empty registry as a runnable node deployment.
Before the client Application can reconcile, operators must publish the
reviewed immutable private GitOps OCI artifacts and run the separately
approved private Argo CD bootstrap phase. The release contract accepts only
the `0.1.<run>` version format; promotion must verify and carry the exact
immutable OCI digest before changing the Application. No historical chart
revision is assumed to exist in a new account.

SSM access, Vault initialization/unseal, Vault writes, validator key custody,
remote-signer activation, and validator duties are deliberately not bootstrap
operations. They require their own command and approval boundary.

## Fresh zero-resource infrastructure

For a new account scope, create the three non-secret configuration files from
the AWS account ID and the exact IAM role that will retain Terraform backend
access. If the current AWS identity is that role, omit
`--backend-principal-arn` and it is derived after an account-match check:

```sh
release/source/scripts/release/prepare-zero-resource-inputs.sh \
  --aws-account-id <new-account-id> \
  --backend-principal-arn arn:aws:iam::<new-account-id>:role/<terraform-role> \
  --output-dir /controlled-input/node-operator-zero
```

Then run one verified command:

```sh
release/source/scripts/release/node-operator-release.sh zero apply \
  --bundle-root release \
  --inputs /controlled-input/node-operator-zero/zero-resource-inputs.json \
  --work-dir /controlled-state/node-operator-zero-bootstrap
```

The command creates and migrates the encrypted Terraform backend, then applies
foundation-network and the baseline. It derives VPC, subnet, route-table, and
NAT inputs from the foundation output; a second VPC is not allowed. The work
directory is a new mode-0700 directory and contains plan/state material, so
retain it under controlled operator storage.

This is infrastructure only. Immutable GitOps artifact publication, private
Argo bootstrap, optional SSM access, Vault initialize/restore, custody, and
validator activation stay separate approved operations.

For the separately managed private EKS operations host, derive its isolated
Terraform inputs from the zero-release work directory rather than copying VPC,
subnet, or backend values by hand. The command verifies the current AWS account
and reads the cluster security group from the EKS control plane:

```sh
release/source/scripts/release/prepare-ops-access-inputs.sh \
  --handoff /controlled-state/node-operator-zero-bootstrap/ops-access-handoff.json \
  --output-dir /controlled-input/node-operator-ops-access
```

Pass `ops-access-inputs.json` to `node-operator-ops-access.sh` with a private
saved-plan location; do not retype its config or backend paths.

After publishing a chart and preparing the digest-bound Argo input, create a
reviewed private plan against the same `--work-dir` used by `zero apply`; only
then apply that exact saved plan:

```sh
scripts/release/apply-argocd-bootstrap.sh plan \
  --baseline-work-dir /controlled-state/node-operator-zero-bootstrap \
  --baseline-config /controlled-input/baseline.tfvars \
  --bootstrap-input /controlled-state/argocd.tfvars.json \
  --plan-file /controlled-state/argocd-bootstrap.tfplan
```

After Argo health and private-CD verification are accepted, revoke the
temporary runner and its cluster-admin association using the original disabled
baseline input and a separately reviewed deletion-only plan.

After `zero apply`, configure the GitOps publisher using the generated
non-secret handoff (it writes only an AWS account ID and restricted OIDC role
ARN to the protected GitHub environment):

```sh
release/source/scripts/release/configure-gitops-publisher.sh \
  --handoff /controlled-state/node-operator-zero-bootstrap/gitops-publisher-handoff.json
```

The protected environment still requires its configured approval before the
publisher can create an immutable chart. Never put GitHub tokens, Vault
material, custody keys, or validator secrets in the handoff.
