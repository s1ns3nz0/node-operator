package nodeoperator.decision_test

import rego.v1
import data.nodeoperator.decision

base_input := {"subject": {"commit_sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}, "evidence": {"gitleaks": {"findings": []}, "osv": {"vulnerabilities": []}, "semgrep": {"findings": []}, "zizmor": {"findings": []}, "checkov": {"failed_checks": []}}, "policy": {"exceptions": []}, "scm": {"changed_files": ["README.md"], "pull_request": {"author": "s1ns3nz0"}, "approvers": []}}

test_clean_evidence_passes if { decision.decision with input as base_input; decision.decision.summary.block == 0 }
test_missing_evidence_blocks if { result := decision.decision with input as object.remove(base_input, ["evidence"]); result.summary.block == 5 }
test_secret_blocks if { fixture := object.union(base_input, {"evidence": object.union(base_input.evidence, {"gitleaks": {"findings": [{"path": "config.env"}]}})}); result := decision.decision with input as fixture; result.summary.block == 1 }
test_critical_vulnerability_blocks if { fixture := object.union(base_input, {"evidence": object.union(base_input.evidence, {"osv": {"vulnerabilities": [{"package": "example", "severity": "CRITICAL", "fix_available": false}]}})}); result := decision.decision with input as fixture; result.summary.block == 1 }
test_high_without_fix_warns if { fixture := object.union(base_input, {"evidence": object.union(base_input.evidence, {"osv": {"vulnerabilities": [{"package": "example", "severity": "HIGH", "fix_available": false}]}})}); result := decision.decision with input as fixture; result.summary.warn == 1 }
test_expired_exception_blocks if { fixture := object.union(base_input, {"policy": {"exceptions": [{"rule": "iac.checkov", "subject": "module.eks", "owner": "fjy", "rationale": "temporary", "issue": "https://github.com/s1ns3nz0/node-operator/issues/1", "expires_at": "2020-01-01T00:00:00Z"}]}}); result := decision.decision with input as fixture; result.summary.block == 1 }
test_sensitive_change_requires_secondary_approval if { fixture := object.union(base_input, {"scm": {"changed_files": ["policy/decision.rego"], "pull_request": {"author": "s1ns3nz0"}, "approvers": []}}); result := decision.decision with input as fixture; result.summary.require_approval == 1 }
test_sensitive_change_rejects_self_approval if { fixture := object.union(base_input, {"scm": {"changed_files": ["policy/decision.rego"], "pull_request": {"author": "s1ns3nz0"}, "approvers": ["s1ns3nz0"]}}); result := decision.decision with input as fixture; result.summary.block == 1 }
