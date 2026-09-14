# Verify artifacts before creating the cluster

- Status: accepted
- Approval: user approved artifact-first deployment and same-state retries on 2026-09-13.
- Owner: primary agent; user-selected Astra planning and Terra implementation override the default Sol routing.
- Specification: [Installer preflight and resume](../product-specs/installer-preflight-resume.md)

## Decision

Validate release inputs and immutable artifact sources, prepare only the minimum private ECR destinations, mirror and verify destination digests, then create the network and EKS. A failed retry must reuse the selected deployment identity and Terraform state, not silently generate another stack. Existing unrelated Terraform infrastructure remains outside scope.

## Boundaries

This implementation task authorizes local code and offline tests only. It does not authorize deployment, publication, merging, secret access, or validator activation. Previously authorized regional deletion is a separate agent task. Recovery ceremonies and deposit transactions must not be replayed automatically.

## Rationale

The reviewed Osaka logs contain repeated infrastructure failures and later artifact/bootstrap failures. Detecting unavailable artifacts after EKS creation wastes infrastructure work; changing deployment identity on retries leaves partial stacks behind.
