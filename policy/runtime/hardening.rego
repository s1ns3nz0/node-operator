package nodeoperator.runtime

import rego.v1

deny contains {"msg": "containers must not run privileged", "id": "kubernetes.privileged"} if { container := input.spec.template.spec.containers[_]; container.securityContext.privileged == true }
deny contains {"msg": "containers must run as non-root", "id": "kubernetes.non-root"} if { container := input.spec.template.spec.containers[_]; not container.securityContext.runAsNonRoot }
deny contains {"msg": "containers must use a read-only root filesystem", "id": "kubernetes.readonly-root"} if { container := input.spec.template.spec.containers[_]; not container.securityContext.readOnlyRootFilesystem }
