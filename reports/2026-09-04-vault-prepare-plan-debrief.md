# Clean-room debrief: Vault bootstrap prepare-plan review

## Observed evidence

- The prepare contract requires `enable_vault_bootstrap_runner=true` and `enable_vault_bootstrap_cluster_admin=false`. The Terraform condition for `AmazonEKSClusterAdminPolicy` is disabled for that combination.
- The runner precondition requires a private GitOps foundation, a digest-pinned `vault_bootstrap_image`, a pinned chart version, and explicit private subnet IDs.
- A read-only Terraform backend initialization and non-secret private-subnet output read succeeded. No secret, credential, certificate, kubeconfig, raw state, or log material was retained.
- The approved OCI artifact manifest contains Vault server and injector images only. It contains neither a dedicated Vault bootstrap toolchain digest nor a Vault Helm chart OCI artifact. The available bootstrap-image value in the offline fixture is explicitly synthetic and prohibited for a live apply.
- The offline prepare-plan contract test and harness structural check passed.

## Inference and conclusion

A refresh-backed live prepare plan cannot be responsibly generated with the available approved inputs. Supplying a syntactically valid but unapproved digest would satisfy Terraform's format precondition without establishing a reproducible, private bootstrap artifact. Keep the plan unapplied and require artifact approval and mirroring first.

## Scope confirmation

No Terraform apply, cloud mutation, EKS access-policy change, CodeBuild run, Helm, kubectl, Vault, secret access, OCI mirror dispatch, merge, or publish occurred.
