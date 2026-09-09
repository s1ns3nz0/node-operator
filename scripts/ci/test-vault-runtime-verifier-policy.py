#!/usr/bin/env python3
"""Strict source contract for the disabled Vault runtime verifier IAM role."""
import re
from pathlib import Path


def block(source, kind, name):
    labels = rf'"{name}"' if kind in {"variable", "output"} else rf'"[^"]+" "{name}"'
    match = re.search(rf'{kind} {labels} \{{\n(.*?)\n\}}', source, re.S)
    assert match, f"{name} {kind} block missing"
    return match[1]


def validate(source):
    variable = block(source, "variable", "enable_vault_runtime_ci_verifier")
    assert re.search(r"type\s*=\s*bool", variable)
    assert re.search(r"default\s*=\s*false", variable)

    trust = block(source, "data", "github_vault_runtime_verifier_assume_role")
    assert 'count = var.enable_vault_runtime_ci_verifier ? 1 : 0' in trust
    assert '"sts:AssumeRoleWithWebIdentity"' in trust
    assert trust.count("statement {") == 1 and trust.count("condition {") == 3
    assert 'arn:aws:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com' in trust
    for expected in (
        '"token.actions.githubusercontent.com:aud"',
        '"sts.amazonaws.com"',
        '"token.actions.githubusercontent.com:repository"',
        '[var.github_repository]',
        '"token.actions.githubusercontent.com:sub"',
        '"${var.github_oidc_subject_prefix}:ref:refs/heads/main"',
    ):
        assert expected in trust, f"OIDC trust condition missing: {expected}"

    role = block(source, "resource", "github_vault_runtime_verifier")
    assert 'count              = var.enable_vault_runtime_ci_verifier ? 1 : 0' in role
    assert 'var.enable_vault_runtime_ecr && var.enable_node_runtime_ecr' in role

    policy = block(source, "data", "github_vault_runtime_verifier")
    statements = re.findall(
        r"statement \{\s*actions\s*=\s*\[([^\]]+)\]\s*resources\s*=\s*([^\n]+)\s*\}",
        policy,
        re.S,
    )
    assert len(statements) == 2 and policy.count("statement {") == 2
    token_actions = re.findall(r'"([^"]+)"', statements[0][0])
    assert token_actions == ["ecr:GetAuthorizationToken"]
    assert statements[0][1].strip() == '["*"]'

    read_actions = set(re.findall(r'"([^"]+)"', statements[1][0]))
    assert read_actions == {
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:DescribeImages",
        "ecr:GetDownloadUrlForLayer",
    }
    assert statements[1][1].strip() == "values(aws_ecr_repository.vault_runtime)[*].arn"

    runtime_repositories = (
        Path(__file__).resolve().parents[2] / "infra/terraform/vault-runtime-ecr.tf"
    ).read_text()
    assert 'toset(["server", "agent", "injector"])' in runtime_repositories, (
        "verifier scope must resolve to exactly the three Vault runtime repositories"
    )

    output = block(source, "output", "github_vault_runtime_ci_verifier_role_arn")
    assert "try(aws_iam_role.github_vault_runtime_verifier[0].arn, null)" in output


source = (Path(__file__).resolve().parents[2] / "infra/terraform/vault-runtime-verifier.tf").read_text()
validate(source)
for bad in (
    source.replace('"ecr:DescribeImages", ', '"ecr:PutImage", '),
    source.replace('values(aws_ecr_repository.vault_runtime)[*].arn', '["*"]'),
    source.replace('var.enable_vault_runtime_ecr && var.enable_node_runtime_ecr', 'true'),
    source.replace(':ref:refs/heads/main', ':environment:vault-runtime-verify'),
    source.replace(':ref:refs/heads/main', ':ref:refs/heads/release'),
    source.replace(':ref:refs/heads/main', ':ref:refs/tags/v1.0.0'),
    source.replace(':ref:refs/heads/main', ':pull_request'),
):
    try:
        validate(bad)
    except AssertionError:
        continue
    raise AssertionError("unsafe verifier policy or trust mutation passed")
print("PASS: Vault runtime verifier is disabled, prerequisite-bound, main-only, and read-only")
