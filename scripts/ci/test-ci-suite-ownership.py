#!/usr/bin/env python3
# Check objective: Keep each required CI suite assigned exactly once to its workflow owner.
"""Keep common required CI suites present exactly once across their owners."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
OWNERS = {
    "ci-policy.yml": ("test-policy.sh", "test-terraform-policy.sh", "test-conftest.sh"),
    "policy-foundation.yml": ("test-normalizer.sh", "test-pr-gate.sh",
                              "test-pr-baseline-findings.sh", "test-dast-target-contract.sh"),
    "ci-quality.yml": ("test-script-quality.sh",),
}


class SuiteOwnership(unittest.TestCase):
    def test_required_suites_have_one_owner(self):
        workflows = {name: (ROOT / ".github/workflows" / name).read_text()
                     for name in OWNERS}
        for owner, scripts in OWNERS.items():
            for script in scripts:
                with self.subTest(script=script):
                    reference = "scripts/ci/" + script
                    self.assertEqual(workflows[owner].count(reference), 1)
                    self.assertEqual(sum(text.count(reference) for text in workflows.values()), 1)
                    self.assertTrue((ROOT / reference).is_file())


if __name__ == "__main__":
    unittest.main()
