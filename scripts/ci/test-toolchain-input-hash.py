# Check objective: Verify toolchain input hashes bind ordered input files without building or publishing images.
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/release/build-toolchain-image.sh"


def expected(*files: Path) -> str:
    rows = "".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}\n" for path in files)
    return hashlib.sha256(rows.encode()).hexdigest()


class ToolchainInputHashTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name)
        self.bin = self.root / "bin"; self.bin.mkdir(); self.calls = self.root / "calls"
        docker = self.bin / "docker"
        docker.write_text('#!/bin/sh\necho "$@" >> "$DOCKER_CALLS"\nexit 0\n')
        docker.chmod(0o755)
        self.dockerfile = self.root / "tool.Dockerfile"; self.dockerfile.write_text("FROM scratch\n")
        self.vault_a = self.root / "values.yaml"; self.vault_a.write_text("a\n")
        self.vault_b = self.root / "helper.sh"; self.vault_b.write_text("b\n")
    def tearDown(self): self.temp.cleanup()
    def invoke(self, *inputs: Path):
        env = os.environ | {"PATH": str(self.bin) + ":" + os.environ["PATH"], "DOCKER_CALLS": str(self.calls), "GITHUB_SHA": "abc", "GITHUB_WORKSPACE": str(self.root), "DOCKERFILE": str(self.dockerfile), "IMAGE": "local/vault", "IMAGE_NAME": "vault-bootstrap", "INPUT_FILE": " ".join(map(str, inputs))}
        return subprocess.run(["bash", str(SCRIPT)], cwd=self.root, env=env, text=True, capture_output=True, check=True)
    def built_hash(self) -> str:
        line = next(x for x in self.calls.read_text().splitlines() if x.startswith("build "))
        return line.split("TOOLCHAIN_INPUT_SHA=", 1)[1].split(" ", 1)[0]
    def test_empty_input_file_hashes_dockerfile_only(self):
        self.invoke(); self.assertEqual((self.root / "toolchain-input.sha256").read_text().strip(), expected(self.dockerfile))
    def test_vault_ordered_multi_path_changes_for_each_helper(self):
        self.invoke(self.vault_a, self.vault_b); first = (self.root / "toolchain-input.sha256").read_text().strip(); self.assertEqual(first, expected(self.dockerfile, self.vault_a, self.vault_b))
        self.calls.unlink(); self.vault_a.write_text("changed-a\n"); self.invoke(self.vault_a, self.vault_b); second = (self.root / "toolchain-input.sha256").read_text().strip(); self.assertNotEqual(first, second)
        self.calls.unlink(); self.vault_b.write_text("changed-b\n"); self.invoke(self.vault_a, self.vault_b); self.assertNotEqual(second, (self.root / "toolchain-input.sha256").read_text().strip())


if __name__ == "__main__": unittest.main()
