#!/usr/bin/env python3
"""Focused source contract with negative mutations, not an end-to-end CI test."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def validate(script, workflow):
    for forbidden in (r"docker\s+(build|push|tag)\b", r"cosign\s+(sign|attest)\b", r"\bkubectl\b", r"terraform\s+apply"):
        assert not re.search(forbidden, script + workflow), "unexpected mutation"
    for required in ("--network none", "--read-only", "--cap-drop ALL", "--security-opt no-new-privileges",
                     "--pids-limit 64", "--memory 512m", "timeout 60 docker run",
                     "--platform linux/amd64", ".RepoDigests | index($subject) != null",
                     ".entrypoint == [$entrypoint]", '"registry:$subject"', '"sbom:$evidence/sbom.json"',
                     "jq -e '.status == \"passed\"'", "unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN",
                     "unset ACTIONS_ID_TOKEN_REQUEST_TOKEN ACTIONS_ID_TOKEN_REQUEST_URL"):
        assert required in script, required
    assert script.index("aws ecr describe-images") < script.index("unset AWS_ACCESS_KEY_ID") < script.index("docker pull")
    assert not re.search(r"^\s*environment:", workflow, re.M), "environment invalidates exact-ref OIDC subject"
    assert "workflow_dispatch:" in workflow and "if: github.ref == 'refs/heads/main'" in workflow
    assert not re.search(r"^\s*(push|pull_request|pull_request_target|workflow_run):", workflow, re.M)
    assert "persist-credentials: false" in workflow and "fail-fast: false" in workflow
    assert "trap cleanup EXIT" in workflow and 'export DOCKER_CONFIG="$scratch/docker"' in workflow
    assert "if: always()" in workflow and "vault-runtime-evidence/*.json" in workflow


script = (ROOT / "scripts/ci/verify-vault-runtime-candidate.sh").read_text()
workflow = (ROOT / ".github/workflows/vault-runtime-candidate-verification.yml").read_text()
validate(script, workflow)
for bad_script, bad_workflow in (
    (script.replace("--network none", "--network host"), workflow),
    (script.replace("--read-only", ""), workflow),
    (script.replace("unset AWS_ACCESS_KEY_ID", "# missing AWS_ACCESS_KEY_ID"), workflow),
    (script.replace(".status == \"passed\"", "true"), workflow),
    (script + "\ndocker push changed\n", workflow),
    (script, workflow + "\n    environment: unsafe\n"),
    (script, workflow.replace("if: github.ref == 'refs/heads/main'", "if: true")),
):
    try:
        validate(bad_script, bad_workflow)
    except AssertionError:
        continue
    raise AssertionError("unsafe verification mutation accepted")
allowlist = json.loads((ROOT / ".ci/vault-runtime-candidates.json").read_text())
assert set(allowlist["candidates"]) == {"server", "agent", "injector"}
for component, candidate in allowlist["candidates"].items():
    assert candidate["repository"] == f"node-operator-baseline-vault-runtime-{component}"
    assert re.fullmatch(r"sha256:[a-f0-9]{64}", candidate["digest"])
print("PASS: frozen runtime wrapper/workflow contract and seven unsafe mutations rejected")
