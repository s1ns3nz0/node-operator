package nodeoperator.decision

import rego.v1

decision := {"violations": violations, "summary": {"block": count([v | some v in violations; v.class == "block"]), "warn": count([v | some v in violations; v.class == "warn"]), "require_approval": count([v | some v in violations; v.class == "require-approval"])}}

violations contains violation if {
  tool := data.nodeoperator.config.required_evidence[_]
  object.get(object.get(input, "evidence", {}), tool, null) == null
  violation := finding("evidence.missing", "block", sprintf("required %s evidence is missing", [tool]), tool, sprintf("evidence.%s", [tool]))
}

violations contains violation if {
  item := object.get(object.get(object.get(input, "evidence", {}), "gitleaks", {}), "findings", [])[_]
  violation := finding("secret.detected", "block", "secret detection finding reported", object.get(item, "path", "unknown"), "evidence.gitleaks")
}

violations contains violation if {
  item := object.get(object.get(object.get(input, "evidence", {}), "checkov", {}), "failed_checks", [])[_]
  not exception_applies("iac.checkov", object.get(item, "resource", "unknown"))
  violation := finding("iac.checkov", "block", object.get(item, "check_name", "IaC policy failure"), object.get(item, "resource", "unknown"), "evidence.checkov")
}

violations contains violation if {
  vulnerability := object.get(object.get(object.get(input, "evidence", {}), "osv", {}), "vulnerabilities", [])[_]
  upper(object.get(vulnerability, "severity", "")) == "CRITICAL"
  violation := finding("vulnerability.critical", "block", "Critical vulnerability reported", object.get(vulnerability, "package", "unknown"), "evidence.osv")
}

violations contains violation if {
  vulnerability := object.get(object.get(object.get(input, "evidence", {}), "osv", {}), "vulnerabilities", [])[_]
  upper(object.get(vulnerability, "severity", "")) == "HIGH"
  object.get(vulnerability, "fix_available", false)
  violation := finding("vulnerability.high-fix", "block", "High vulnerability has an available fix", object.get(vulnerability, "package", "unknown"), "evidence.osv")
}

violations contains violation if {
  vulnerability := object.get(object.get(object.get(input, "evidence", {}), "osv", {}), "vulnerabilities", [])[_]
  severity := upper(object.get(vulnerability, "severity", ""))
  severity in {"MEDIUM", "LOW"}
  violation := finding("vulnerability.review", "warn", sprintf("%s vulnerability reported", [severity]), object.get(vulnerability, "package", "unknown"), "evidence.osv")
}

violations contains violation if {
  vulnerability := object.get(object.get(object.get(input, "evidence", {}), "osv", {}), "vulnerabilities", [])[_]
  upper(object.get(vulnerability, "severity", "")) == "HIGH"
  not object.get(vulnerability, "fix_available", false)
  violation := finding("vulnerability.review", "warn", "HIGH vulnerability reported without an available fix", object.get(vulnerability, "package", "unknown"), "evidence.osv")
}

violations contains violation if {
  item := object.get(object.get(object.get(input, "evidence", {}), "zizmor", {}), "findings", [])[_]
  violation := finding("workflow.unsafe", "block", object.get(item, "message", "unsafe workflow finding"), object.get(item, "path", "unknown"), "evidence.zizmor")
}

violations contains violation if {
  exception := object.get(object.get(input, "policy", {}), "exceptions", [])[_]
  invalid_exception(exception)
  violation := finding("exception.invalid", "block", "exception must include rule, subject, owner, rationale, issue, and an unexpired RFC3339 expiry within 30 days", object.get(exception, "subject", "unknown"), "policy.exceptions")
}

violations contains violation if {
  sensitive_change
  author := object.get(object.get(object.get(input, "scm", {}), "pull_request", {}), "author", "")
  author != ""
  approver := object.get(object.get(input, "scm", {}), "approvers", [])[_]
  approver == author
  violation := finding("review.self-approval", "block", "pull request author cannot approve a sensitive-path change", author, "scm.approvers")
}

violations contains violation if {
  sensitive_change
  not "fjybjinsu" in object.get(object.get(input, "scm", {}), "approvers", [])
  violation := finding("review.sensitive-path", "require-approval", "sensitive-path change requires @fjybjinsu approval", "sensitive-path", "scm.approvers")
}

sensitive_change if {
  path := object.get(object.get(input, "scm", {}), "changed_files", [])[_]
  prefix := data.nodeoperator.config.sensitive_path_prefixes[_]
  startswith(path, prefix)
}

invalid_exception(exception) if {
  required := ["rule", "subject", "owner", "rationale", "issue", "expires_at"][_]
  not object.get(exception, required, "")
}

invalid_exception(exception) if {
  expires_at := time.parse_rfc3339_ns(object.get(exception, "expires_at", ""))
  expires_at <= time.now_ns()
}

invalid_exception(exception) if {
  expires_at := time.parse_rfc3339_ns(object.get(exception, "expires_at", ""))
  expires_at > time.now_ns() + data.nodeoperator.config.exception_maximum_ttl_hours * 3600000000000
}

exception_applies(rule, subject) if {
  exception := object.get(object.get(input, "policy", {}), "exceptions", [])[_]
  exception.rule == rule
  exception.subject == subject
  not invalid_exception(exception)
}

finding(id, class, reason, subject, evidence_ref) := {"id": id, "class": class, "reason": reason, "subject": subject, "evidence_ref": evidence_ref}
