# Scoped recovery dispositions

1. Keep mandatory IAM, default security group and flow-log fixes in PR149.
2. Review basic-monitoring preference and AWS-documented ECR starport endpoint exception only, with exact file/resource/check binding and expiry.
3. Merge through existing independent-approval gate before PR149 consumes the trusted-base dispositions. No self-authorizing PR exception or scanner suppression.
