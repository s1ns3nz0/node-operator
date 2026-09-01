package nodeoperator.config

import rego.v1

required_evidence := ["gitleaks", "osv", "semgrep", "zizmor", "checkov"]
exception_maximum_ttl_hours := 720
sensitive_path_prefixes := ["policy/", ".github/", "infra/", "kubernetes/"]
