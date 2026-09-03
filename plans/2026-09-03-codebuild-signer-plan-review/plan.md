# CodeBuild signer plan review

1. Identify the exact enablement inputs and distinguish synthetic offline values from deployment values.
2. Add a non-secret offline fixture that enables the signer with the published image digest and syntactically valid private subnet IDs.
3. Produce and review the offline plan, including resource-boundary assertions.
4. Record the live-plan prerequisite list and obtain a clean-room debrief.

This task performs no cloud access or Terraform apply.
