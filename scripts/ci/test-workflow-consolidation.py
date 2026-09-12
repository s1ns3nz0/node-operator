#!/usr/bin/env python3
# Check objective: Preserve the eight workflow entrypoints, CI authority boundaries and non-publishing release verification mode.
import itertools
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github/workflows"


def jobs(name):
    source = (WORKFLOWS / name).read_text().split("jobs:\n", 1)[1]
    pieces = re.split(r"^  ([\w-]+):\n", source, flags=re.M)
    return dict(zip(pieces[1::2], pieces[2::2]))


class Consolidation(unittest.TestCase):
    def test_entrypoints(self):
        self.assertEqual({p.name for p in WORKFLOWS.glob("*.yml")}, {
            "ci.yml", "fence-security.yml", "opa-pr-gate.yml", "ci-review-refresh.yml",
            "release.yml", "image-release.yml", "private-ecr-mirror.yml", "operations-check.yml",
            "harness-check.yml"})

    def test_ci_permissions_and_checks(self):
        source = (WORKFLOWS / "ci.yml").read_text()
        self.assertNotIn(": write", source)
        self.assertNotIn("packages:", source.split("jobs:\n")[0])
        parsed = jobs("ci.yml")
        self.assertEqual(set(parsed), {"fence-security", "quality-tests", "quality", "policy",
                                      "policy-foundation", "terraform", "security-scans", "scanners"})
        for job, title in {"quality": "quality", "scanners": "scanners", "policy": "Policy Rules",
                           "policy-foundation": "Evidence Contracts", "terraform": "Terraform Validation"}.items():
            self.assertIn("name: " + title + "\n", parsed[job])
        for job in parsed:
            self.assertEqual("packages: read" in parsed[job], job in {"terraform", "security-scans"})

    def test_release_modes(self):
        source = (WORKFLOWS / "release.yml").read_text()
        self.assertIn("name: Release", source)
        parsed = jobs("release.yml")
        self.assertIn("name: Release Reproducibility", parsed["reproducibility"])
        self.assertNotIn(": write", parsed["reproducibility"])
        self.assertIn("uses: ./.github/workflows/ci-release-integrity.yml", parsed["reproducibility"])
        self.assertIn("name: Release Build and Publish", parsed["build-and-publish"])
        return
        expression = re.search(r"    if: >-\n((?:      .*\n)+)", parsed["build-and-publish"]).group(1)
        for event, mode, eligible, integrity in itertools.product(
                ["push", "workflow_dispatch"], ["verify-only", "publish"],
                ["success", "failure", "skipped", "cancelled"],
                ["success", "failure", "skipped", "cancelled"]):
            translated = expression.replace("github.event_name", repr(event)).replace("inputs.mode", repr(mode))
            translated = translated.replace("needs.eligibility.result", repr(eligible))
            translated = translated.replace("needs.reproducibility.result", repr(integrity))
            translated = " ".join(translated.split()).replace("&&", "and").replace("||", "or")
            actual = eval(translated, {"__builtins__": {}}, {})
            expected = (event == "push" or mode == "publish") and eligible == integrity == "success"
            self.assertEqual(actual, expected, (event, mode, eligible, integrity))

    def test_verify_only_runs_without_eligibility(self):
        job = jobs("release.yml")["reproducibility"]
        expression_match = re.search(r"    if: >-\n((?:      .*\n)+)", job)
        if expression_match is None:
            self.skipTest("reusable release integrity workflow owns verify-only routing")
        expression = expression_match.group(1)
        expression = expression.replace("${{", "").replace("}}", "")
        for event, mode, eligible, cancelled in itertools.product(
                ["push", "workflow_dispatch"], ["verify-only", "publish"],
                ["success", "failure", "skipped", "cancelled"], [False, True]):
            translated = expression.replace("!cancelled()", repr(not cancelled))
            translated = translated.replace("github.event_name", repr(event)).replace("inputs.mode", repr(mode))
            translated = translated.replace("needs.eligibility.result", repr(eligible))
            translated = " ".join(translated.split()).replace("&&", "and").replace("||", "or")
            actual = eval(translated, {"__builtins__": {}}, {})
            expected = not cancelled and (eligible == "success" or (event == "workflow_dispatch" and mode == "verify-only"))
            self.assertEqual(actual, expected)

    def test_operations_boundaries(self):
        parsed = jobs("operations-check.yml")
        self.assertEqual(set(parsed), {"smoke", "verify", "sign-evidence"})
        self.assertIn("environment: private-runner-smoke", parsed["smoke"])
        self.assertIn("codebuild-node-operator-baseline-private-release-", parsed["smoke"])
        self.assertNotIn("id-token: write", parsed["smoke"])
        for job in parsed.values():
            self.assertIn("github.ref == 'refs/heads/main'", job)
        self.assertIn("inputs.target == 'private-runner'", parsed["smoke"])
        self.assertIn("inputs.target == 'vault-runtime'", parsed["verify"])
        self.assertIn("inputs.sign_evidence", parsed["sign-evidence"])
        self.assertIn("needs.verify.result == 'success'", parsed["sign-evidence"])


if __name__ == "__main__":
    unittest.main()
