#!/usr/bin/env bash
# Check objective: Verify private runner access to required AWS service APIs without changing resources.
set -euo pipefail

set -eu
aws sts get-caller-identity --query Account --output text >/dev/null
aws eks describe-cluster --name node-operator --query 'cluster.status' --output text | grep -qx ACTIVE
aws ecr get-authorization-token --query 'authorizationData[0].proxyEndpoint' --output text >/dev/null
aws logs describe-log-groups --log-group-name-prefix /aws/codebuild/ --max-items 1 >/dev/null
