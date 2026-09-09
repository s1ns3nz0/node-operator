#!/usr/bin/env python3
"""No-cluster tests for live canary execution and rejection guards."""
import contextlib
import copy
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
from unittest.mock import patch

sys.dont_write_bytecode = True
path = Path(__file__).resolve().parents[1] / "ops/test-private-vault-injector-canary.py"
spec = importlib.util.spec_from_file_location("canary", path)
canary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(canary)


def refused(callback, code=1):
    with contextlib.redirect_stderr(io.StringIO()):
        try:
            callback()
        except SystemExit as error:
            assert error.code == code
        else:
            raise AssertionError("unsafe input accepted")


with patch.object(canary, "command", side_effect=AssertionError("external command invoked")), patch.object(canary.os, "execvpe", side_effect=AssertionError("tunnel invoked")):
    for arguments in ([], ["--execute", "unexpected"], ["--dry-run"]):
        with patch.object(sys, "argv", [str(path)] + arguments):
            refused(canary.main, 64)
    with patch.object(sys, "argv", [str(path), "--help"]), contextlib.redirect_stdout(io.StringIO()):
        canary.main()

name = "synthetic.node-operator.invalid"
for status, error in ((0, ""), (1, "timeout"), (1, f'failed calling webhook "{name}"'), (1, 'other webhook denied the request')):
    result = subprocess.CompletedProcess([], status, "", error)
    refused(lambda: canary.require_annotation_denial(result, name))
canary.require_annotation_denial(subprocess.CompletedProcess([], 1, "", f'admission webhook "{name}" denied the request: invalid syntax'), name)

baseline = {"metadata": {"uid": canary.GLOBAL_WEBHOOK_UID}, "webhooks": [{"failurePolicy": "Ignore", "objectSelector": {
    "matchExpressions": [{"key": "app.kubernetes.io/name", "operator": "NotIn", "values": ["vault-agent-injector"]}]}}]}
with patch.object(canary, "kubectl_json", return_value=baseline):
    assert canary.expect_global_webhook() == canary.webhook_hash(baseline)
for mutation in ("uid", "extra", "selector", "policy"):
    changed = copy.deepcopy(baseline)
    if mutation == "uid": changed["metadata"]["uid"] = "other"
    if mutation == "extra": changed["webhooks"].append(copy.deepcopy(changed["webhooks"][0]))
    if mutation == "selector": changed["webhooks"][0]["objectSelector"] = {}
    if mutation == "policy": changed["webhooks"][0]["failurePolicy"] = "Fail"
    with patch.object(canary, "kubectl_json", return_value=changed):
        refused(canary.expect_global_webhook)
print("PASS: no-write CLI guard, explicit admission denial and global webhook drift guards (mocked, not live canary)")
