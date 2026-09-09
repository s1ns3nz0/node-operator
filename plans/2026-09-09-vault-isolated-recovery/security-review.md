# Independent recovery infrastructure review

Terra `recovery_iac_review` accepted the infrastructure-only boundary after
review of all six module files. Requested hardening was implemented: exact
AWS AMI owner, service-specific SSM endpoint actions, transport KMS endpoint
context constraints and explicit root-volume deletion at instance termination.

The workload role has no KMS grant/key-policy management or Parameter Store
read access. The regional ECR layer bucket requires wildcard principal in the
S3 gateway endpoint because layer URLs are presigned by ECR; object scope is
limited to that AWS regional bucket, not the snapshot bucket. Sensitive snapshot
and KMS use is explicitly denied after the configured recovery expiry. Expiry
does not delete resources or revoke the separate temporary KMS grant; both must
be tracked and cleaned up through their own reviewed lifecycle.

Live read-only key-policy inspection through the existing Terraform role
confirmed that the auto-unseal key does not delegate use via account IAM.
The snapshot transport key does. No key policy was modified; no grant issued.
Temporary unseal permission is a distinct prerequisite, not an inferred success
from attaching this IAM policy. The user explicitly approved this resource and
permission scope; grant execution and restore remain pending.

Pinned Terraform 1.5.7 offline validation and formatting passed. Root also ran
parsed-HCL positive/negative boundary tests in a local scanner container. CI
runs these tests in its existing immutable scanner image, without networking
or credentials. A refresh-backed saved plan must still be reviewed before apply.

No actual snapshot data, recovery keys or credentials were accessed. No
existing live resource is declared under this Terraform root.

Hosted OPA run34346259906 identified eight new IaC findings. The subsequent
reviewed revision fixes default-SG isolation, adds ALL flow logging encrypted
with a new recovery-only KMS key (365-day retention), and scopes SSM update
permission by instance ARN and source VPC. The original 20-create saved plan is
superseded and must not be applied. A new saved plan and review are required.
Only user-selected basic monitoring and AWS-documented regional ECR layer
endpoint access require the separate exact-path disposition change. Neither
disposition is active merely because PR149 proposes infrastructure needing it.
