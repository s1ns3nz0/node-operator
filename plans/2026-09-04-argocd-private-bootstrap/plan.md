# Private Argo CD bootstrap

1. Define a dedicated VPC-internal CodeBuild executor and its digest-pinned toolchain.
2. Grant the executor only EKS access required to create and read Argo CD resources.
3. Render the private ECR chart and image override, rejecting external image references and public services.
4. Apply from the VPC path and record only non-sensitive readiness evidence.
5. Do not create an Argo CD Application or deploy Vault/workloads in this task.
