#!/usr/bin/env python3
# Check objective: Verify selective image builds, conservative push baselines and privileged publication boundaries without building or publishing images.
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("selection", ROOT / "scripts/ci/select-image-release.py")
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


class Selection(unittest.TestCase):
    def test_unrelated_changes_select_nothing(self):
        result = M.select(["README.md", "docs/operations/guide.md"])
        self.assertFalse(any(result[key] for key in ("scanner", "toolchains", "fence", "relay")))

    def test_each_toolchain_is_selected_individually(self):
        for item in M.TOOLCHAINS:
            for path in (item["dockerfile"], item["input_file"]):
                if not path:
                    continue
                with self.subTest(path=path):
                    result = M.select([path])
                    self.assertEqual(result["toolchain_matrix"]["include"], [item])
                    self.assertFalse(result["scanner"] or result["fence"] or result["relay"])

    def test_runtime_targets_are_independent(self):
        for path, target in (("cmd/validator-signing-fence/main.go", "fence"),
                             ("cmd/vault-audit-relay/main.go", "relay"),
                             (".ci/scanners/Dockerfile", "scanner")):
            result = M.select([path])
            self.assertTrue(result[target])
            self.assertEqual(sum(result[key] for key in ("scanner", "toolchains", "fence", "relay")), 1)

    def test_shared_inputs_and_manual_choices(self):
        for path in M.SHARED:
            result = M.select([path])
            self.assertTrue(all(result[key] for key in ("scanner", "toolchains", "fence", "relay")))
        result = M.select(["go.mod"])
        self.assertTrue(result["fence"] and result["relay"])
        self.assertFalse(result["scanner"] or result["toolchains"])
        self.assertEqual(len(M.select(target="toolchains")["toolchain_matrix"]["include"]), 6)
        self.assertEqual(len(M.select(target="vault-bootstrap")["toolchain_matrix"]["include"]), 1)
        for target in ("scanner", "fence", "relay"):
            result = M.select(target=target)
            self.assertEqual(sum(result[key] for key in ("scanner", "toolchains", "fence", "relay")), 1)
        with self.assertRaises(ValueError):
            M.select(target="$(unsafe)")

    def test_baseline_and_event_guards(self):
        sha = "a" * 40
        with patch.object(M, "git", return_value=(sha + "\n").encode()):
            result = M.from_event("push", {"after": sha, "before": "0" * 40}, sha)
            self.assertTrue(result["scanner"] and result["relay"])
            for event, body in (("pull_request", {}), ("push", {"after": "b" * 40}),
                                ("push", {"after": sha, "before": "invalid"})):
                with self.assertRaises(ValueError):
                    M.from_event(event, body, sha)
        with patch.object(M, "git", side_effect=[sha.encode(), subprocess.CalledProcessError(1, "git")]):
            self.assertTrue(M.from_event("push", {"after": sha, "before": "b" * 40}, sha)["toolchains"])
        with patch.object(M, "git", return_value=b"different"):
            with self.assertRaises(ValueError):
                M.from_event("workflow_dispatch", {}, sha)

    def test_real_git_diff_and_cli_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=path, stderr=subprocess.DEVNULL).decode().strip()
            git("init", "-q")
            git("config", "user.name", "Synthetic CI Test")
            git("config", "user.email", "ci@example.invalid")
            (path / "README.md").write_text("fixture\n")
            git("add", ".")
            git("commit", "-qm", "baseline")
            before = git("rev-parse", "HEAD")
            (path / ".ci/toolchains").mkdir(parents=True)
            (path / ".ci/toolchains/terraform-validation.Dockerfile").write_text("fixture\n")
            git("add", ".")
            git("commit", "-qm", "changed input")
            after = git("rev-parse", "HEAD")
            event, output = path / "event.json", path / "output"
            event.write_text(json.dumps({"before": before, "after": after}))
            result = subprocess.run(["python3", str(ROOT / "scripts/ci/select-image-release.py")], cwd=path,
                                    env=dict(os.environ, GITHUB_EVENT_NAME="push", GITHUB_EVENT_PATH=str(event),
                                             GITHUB_SHA=after, GITHUB_OUTPUT=str(output)), capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            outputs = dict(line.split("=", 1) for line in output.read_text().splitlines())
            self.assertEqual(outputs["scanner"], "false")
            self.assertEqual(outputs["toolchains"], "true")
            self.assertEqual(json.loads(outputs["toolchain_matrix"])["include"][0]["image"], "terraform-validation")


class Workflow(unittest.TestCase):
    def test_single_workflow_retains_separate_privileges(self):
        source = (ROOT / ".github/workflows/image-publish.yml").read_text()
        jobs = dict(re.findall(r"^  ([\w-]+):\n([\s\S]*?)(?=^  [\w-]+:\n|\Z)", source.split("jobs:\n", 1)[1], re.M))
        self.assertEqual(set(jobs), {"select", "scanner-build", "scanner-publish", "toolchain-build",
                                    "toolchain-publish", "fence-security", "fence-publish", "relay-publish"})
        for name in ("select", "scanner-build", "toolchain-build", "fence-security"):
            self.assertNotIn(": write", jobs[name])
        for name in ("scanner-publish", "toolchain-publish", "fence-publish", "relay-publish"):
            self.assertIn("github.ref == 'refs/heads/main'", jobs[name])
            self.assertNotIn("if: always()", jobs[name].split("steps:")[0])
        for kind in ("scanner", "toolchain"):
            self.assertIn(f"needs: [select, {kind}-build]", jobs[kind + "-publish"])
            self.assertIn(f"needs.{kind}-build.result == 'success'", jobs[kind + "-publish"])
            self.assertIn("packages: write", jobs[kind + "-publish"])
            self.assertNotIn("id-token: write", jobs[kind + "-publish"])
        self.assertIn("needs: [select, fence-security]", jobs["fence-publish"])
        self.assertIn("needs.fence-security.result == 'success'", jobs["fence-publish"])
        self.assertIn("uses: ./.github/workflows/fence-security.yml", jobs["fence-security"])
        self.assertIn("environment: validator-client-ecr-mirror", jobs["fence-publish"])
        self.assertIn("environment: vault-audit-relay-ecr-publish", jobs["relay-publish"])
        for name in ("fence-publish", "relay-publish"):
            self.assertIn("id-token: write", jobs[name])
            self.assertNotIn("packages: write", jobs[name])
        for name in ("toolchain-build", "toolchain-publish"):
            self.assertIn("fromJSON(needs.select.outputs.toolchain_matrix)", jobs[name])
            self.assertIn("needs.select.outputs.toolchains == 'true'", jobs[name])


if __name__ == "__main__":
    unittest.main()
