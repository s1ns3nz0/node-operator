# Terraform backend state diagnosis

1. Confirm the configured temporary Terraform-role profile exists and inspect its STS identity.
2. Read only the backend prefix/object metadata and version metadata.
3. List Terraform state addresses with locking disabled; never show or save raw state values.
4. Record the state-routing conclusion and obtain an independent clean-room debrief.

No state, lock, cloud-resource, registry, or secret mutation is allowed.
