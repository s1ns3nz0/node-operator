package nodeoperator.config

import rego.v1

required_evidence := ["gitleaks", "osv", "semgrep", "zizmor", "checkov", "format", "terraform"]
exception_maximum_ttl_hours := 720
sensitive_path_prefixes := ["policy/", ".github/", "infra/", "kubernetes/"]
