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

For a new account scope, copy the three non-secret
`release/zero-resource-*.tfvars.example` files outside the extracted release,
then run one verified command:

```sh
release/source/scripts/release/node-operator-release.sh zero apply \
  --bundle-root release \
  --bootstrap-config /controlled-input/bootstrap-state.tfvars \
  --foundation-config /controlled-input/foundation-network.tfvars \
  --baseline-config /controlled-input/baseline.tfvars \
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
