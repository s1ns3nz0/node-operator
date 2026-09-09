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
approved private Argo CD bootstrap phase. The release contract pins the client
chart revision to `0.1.32`; promotion must verify that exact immutable artifact
before changing the Application.

SSM access, Vault initialization/unseal, Vault writes, validator key custody,
remote-signer activation, and validator duties are deliberately not bootstrap
operations. They require their own command and approval boundary.
