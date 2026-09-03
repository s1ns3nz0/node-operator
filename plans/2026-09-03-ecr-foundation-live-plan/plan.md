# ECR signer foundation live-plan review

1. Confirm the active AWS identity and approved remote backend without mutating cloud state.
2. Generate an ephemeral non-secret input that enables only the ECR mirror foundation and keeps the signer disabled.
3. Run Terraform init and a saved plan with state locking disabled; review its JSON summary for allowed resource actions.
4. Record non-sensitive evidence, or an access/configuration blocker, and obtain an independent clean-room debrief.

Terraform apply, image mirroring, and GitHub Environment mutation are excluded.
