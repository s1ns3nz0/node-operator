# Clean-room debrief: temporary SSM operations host

## Scope

This is a clean-room review of task `2026-09-04-temporary-ssm-ops-host`. It considered only the completed task bundle, the specified Terraform files, and their `git diff HEAD` output. No AWS, Terraform plan/apply, Kubernetes, SSM, or unrelated repository history was accessed.

## Evidence accepted

The task bundle records successful Terraform format/validation, a refresh-backed saved-plan allowlist and boundary assertions, an independent Terra review, a corrective saved-plan gate and exact-plan apply, and post-apply verification. The stated post-apply checks confirm no public IP, zero inbound host-security-group rules, an online SSM managed instance, and an enabled one-time Scheduler target using `ec2:TerminateInstances` at `at(2026-09-04T22:00:00)` in `Asia/Seoul`.

The reviewed Terraform is consistent with that evidence: the instance is in the approved private subnet with `associate_public_ip_address = false`, no SSH key or user data, a dedicated SSM instance profile, IMDSv2 required, and encrypted storage. Its security group declares no ingress; only HTTPS egress to the private SSM endpoints and private cluster security group is configured. The destination security-group rules allow only HTTPS from this host. The Scheduler role is limited to terminating this specific instance and is restricted to Scheduler requests from the approved account and default schedule group.

## Boundary conclusion

The temporary path remains private, has no inbound rule, and is time-bounded. It is an SSM TCP-tunnel target rather than a host for persisted Kubernetes credentials or secret material. The automatic action is termination, not stop, so the host cannot remain a restartable administrative path after the scheduled time.

## Unresolved issues

No unresolved private/no-inbound/time-bounded implementation boundary was identified from the permitted evidence. The task bundle was subsequently updated to use consistent one-time termination terminology. The scheduler trust policy uses the default schedule-group ARN rather than the individual schedule ARN because the recorded corrective apply establishes that Scheduler supplies the schedule-group ARN during role validation. Its permission remains restricted to this one instance.
