package nodeoperator.runtime_test

import rego.v1
import data.nodeoperator.runtime

secure_workload := {"spec": {"template": {"spec": {"containers": [{"securityContext": {"privileged": false, "runAsNonRoot": true, "readOnlyRootFilesystem": true}}]}}}}
test_hardened_workload_passes if { denial := runtime.deny with input as secure_workload; count(denial) == 0 }
test_privileged_workload_fails if { insecure := object.union(secure_workload, {"spec": {"template": {"spec": {"containers": [{"securityContext": {"privileged": true, "runAsNonRoot": true, "readOnlyRootFilesystem": true}}]}}}}); denial := runtime.deny with input as insecure; denial[_].id == "kubernetes.privileged" }
