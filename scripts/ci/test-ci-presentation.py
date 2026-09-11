#!/usr/bin/env python3
# Check objective: Keep workflow display labels consistent and preserve event-routing names.
"""Check presentation conventions without adding a YAML parser dependency."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github/workflows"


class Presentation(unittest.TestCase):
    def test_workflow_titles(self):
        for path in WORKFLOWS.glob("*.yml"):
            with self.subTest(workflow=path.name):
                title = re.search(r"^name: (.+)$", path.read_text(), re.M)
                self.assertIsNotNone(title)
                self.assertRegex(title[1], r"^(CI|Release|Mirror) [A-Za-z].+")

    def test_named_step_phases(self):
        for path in WORKFLOWS.glob("*.yml"):
            for title in re.findall(r"^\s+- name: (.+)$", path.read_text(), re.M):
                with self.subTest(workflow=path.name, step=title):
                    self.assertRegex(title, r"^(Prepare|Check|Build|Evidence|Publish) \| .+")

    def test_workflow_run_identity_bindings(self):
        for producer, consumer, title in (
            ("ci-security.yml", "opa-pr-gate.yml", "CI Security"),
            ("ci-review-refresh.yml", "ci-review-refresh-handler.yml", "CI Evidence Review Signal"),
        ):
            with self.subTest(producer=producer):
                self.assertIn("name: " + title + "\n", (WORKFLOWS / producer).read_text())
                self.assertIn("workflows: [" + title + "]", (WORKFLOWS / consumer).read_text())

    def test_direct_check_entrypoints_document_their_objective(self):
        references = set()
        for path in WORKFLOWS.glob("*.yml"):
            references.update(re.findall(
                r"scripts/ci/(?:test-|verify-|run-|scan-|collect-|validate-|evaluate-|filter-|normalize-)[A-Za-z0-9_.-]+\.(?:sh|py)",
                path.read_text(),
            ))
        self.assertTrue(references)
        for reference in sorted(references):
            with self.subTest(script=reference):
                header = "\n".join((ROOT / reference).read_text().splitlines()[:12])
                self.assertRegex(header, r"(?m)^# Check objective: [A-Z].+\.$")


if __name__ == "__main__":
    unittest.main()
