# Check objective: Exercise installer start, status and resume without cloud calls or credentials.
"""Exercise the installer command path without cloud calls or credentials."""
import contextlib
import importlib
import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "release"))
cli = importlib.import_module("interactive_deploy")
RELEASE = {"release_sha": "a" * 40, "bundle_digest": "sha256:" + "b" * 64}
DISCOVERY = {"aws_profile": "test", "aws_account_id": "123456789012", "aws_region": "ap-northeast-1", "deployment_name": "test-node"}


class InstallerCommandTests(unittest.TestCase):
    def test_artifact_mirror_requires_separate_tty_scope(self):
        with patch.object(cli.sys.stdin, "isatty", return_value=False), patch.object(cli, "discover") as discover, self.assertRaises(cli.StateError):
            cli.run(["resume", "--state-dir", "/unused", "--mirror-vault-artifacts"])
        discover.assert_not_called()
    def test_vault_apply_confirmation_and_partial_failure_never_mark_ready(self):
        for outcome in ("cancel", "failure", "success"):
            with self.subTest(outcome=outcome), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary).resolve() / "state"
                store = cli.CheckpointStore(directory, {**DISCOVERY, **RELEASE})
                with store.lock():
                    store.resume()
                    store.set_stage("infrastructure", "complete")
                    store.set_stage("ops_access", "complete")
                apply = Mock(side_effect=cli.InfrastructureError("uncertain apply") if outcome == "failure" else None)
                bundle = types.SimpleNamespace(verify_release=lambda _: RELEASE, materialize_release=Mock(return_value=directory / "release"))
                digest = "c" * 64
                phrase = f"APPLY VAULT PREPARE 123456789012 ap-northeast-1 test-node {digest}"
                with patch.dict(sys.modules, {"installer_bundle": bundle, "installer_vault_execution": types.SimpleNamespace(apply_vault_prepare=apply)}), patch.object(cli, "discover", return_value=DISCOVERY), patch.object(cli.sys.stdin, "isatty", return_value=True), patch.object(cli, "prompt", return_value="no" if outcome == "cancel" else phrase):
                    args = ["--release-dir", temporary, "--apply-vault", "--vault-artifacts", str(directory / "artifacts.json"), "--vault-plan-sha", digest]
                    if outcome == "success":
                        _, result = self.invoke(directory, "resume", args)
                        self.assertEqual(result["result"], "vault_bootstrap_provisioned")
                        self.assertFalse(result["deployment_complete"])
                    else:
                        with self.assertRaises(cli.StateError if outcome == "cancel" else cli.InfrastructureError):
                            self.invoke(directory, "resume", args)
                    if outcome == "cancel":
                        apply.assert_not_called()
                    else:
                        apply.assert_called_once_with(directory / "release", directory, DISCOVERY, "test", directory / "artifacts.json", digest)
                        _, status = self.invoke(directory, "status")
                        self.assertEqual(status["stages"]["vault"]["status"], "awaiting_input")

    def test_vault_apply_rejects_invalid_scope_before_discovery(self):
        base = ["--apply-vault", "--vault-artifacts", "/unused", "--vault-plan-sha", "a" * 64]
        for tty, options in ((False, base), (True, base + ["--plan-vault"]),
                             (True, base + ["--apply-infrastructure"]),
                             (True, base + ["--verify-ops-access"]),
                             (True, ["--vault-plan-sha", "a" * 64]),
                             (True, base[:-1] + ["bad"])):
            with patch.object(cli.sys.stdin, "isatty", return_value=tty), patch.object(cli, "discover") as discover, self.assertRaises(cli.StateError):
                cli.run(["resume", "--state-dir", "/unused", *options])
            discover.assert_not_called()

    def test_vault_plan_returns_hash_without_readiness_and_recovers_failed_stage(self):
        for failure in (False, True):
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary).resolve() / "state"
                store = cli.CheckpointStore(directory, {**DISCOVERY, **RELEASE})
                with store.lock():
                    store.resume()
                    store.set_stage("infrastructure", "complete")
                    store.set_stage("ops_access", "complete")
                plan = Mock(return_value="c" * 64, side_effect=cli.InfrastructureError("drift") if failure else None)
                bundle = types.SimpleNamespace(verify_release=lambda _: RELEASE, materialize_release=Mock(return_value=directory / "release"))
                with patch.dict(sys.modules, {"installer_bundle": bundle, "installer_vault_execution": types.SimpleNamespace(plan_vault_prepare=plan)}), patch.object(cli, "discover", return_value=DISCOVERY):
                    args = ["--release-dir", temporary, "--plan-vault", "--vault-artifacts", str(directory / "artifacts.json")]
                    if failure:
                        with self.assertRaises(cli.InfrastructureError): self.invoke(directory, "resume", args)
                    else:
                        _, result = self.invoke(directory, "resume", args)
                        self.assertEqual(result["vault_plan_sha256"], "c" * 64)
                        self.assertEqual(result["result"], "vault_bootstrap_plan_ready")
                        self.assertFalse(result["deployment_complete"])
                _, status = self.invoke(directory, "status")
                self.assertEqual(status["stages"]["vault"]["status"], "awaiting_input")

    def test_vault_preparation_requires_completed_access_and_never_claims_ready(self):
        for ready in (False, True):
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary).resolve() / "state"
                store = cli.CheckpointStore(directory, {**DISCOVERY, **RELEASE})
                with store.lock():
                    store.resume()
                    store.set_stage("infrastructure", "complete")
                    store.set_stage("ops_access", "complete" if ready else "pending")
                prepare = Mock()
                bundle = types.SimpleNamespace(verify_release=lambda _: RELEASE)
                with patch.dict(sys.modules, {"installer_bundle": bundle, "installer_vault_inputs": types.SimpleNamespace(prepare_vault_inputs=prepare)}), patch.object(cli, "discover", return_value=DISCOVERY):
                    options = ["--release-dir", temporary, "--prepare-vault", "--vault-artifacts", str(directory / "artifacts.json")]
                    if not ready:
                        with self.assertRaises(cli.StateError):
                            self.invoke(directory, "resume", options)
                        prepare.assert_not_called()
                    else:
                        _, result = self.invoke(directory, "resume", options)
                        self.assertEqual(result["result"], "vault_bootstrap_inputs_ready")
                        self.assertFalse(result["deployment_complete"])
                        prepare.assert_called_once_with(directory, DISCOVERY, directory / "artifacts.json")
                        _, state = self.invoke(directory, "status")
                        self.assertEqual(state["stages"]["vault"]["status"], "awaiting_input")

    def test_vault_preparation_rejects_mixed_operations_before_discovery(self):
        for options in (["--prepare-vault"], ["--vault-artifacts", "/unused"],
                        ["--prepare-vault", "--vault-artifacts", "/unused", "--plan-ops-access"]):
            with patch.object(cli, "discover") as discover, self.assertRaises(cli.StateError):
                cli.run(["resume", "--state-dir", "/unused", *options])
            discover.assert_not_called()

    def test_missing_materializer_downgrades_completed_recheck(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve() / "state"
            store = cli.CheckpointStore(directory, {**DISCOVERY, **RELEASE})
            with store.lock():
                store.resume()
                store.set_stage("infrastructure", "complete")
                store.set_stage("ops_access", "complete")
            bundle = types.SimpleNamespace(verify_release=lambda _: RELEASE)
            with patch.dict(sys.modules, {"installer_bundle": bundle}), patch.object(cli, "discover", return_value=DISCOVERY), self.assertRaises(ImportError):
                self.invoke(directory, "resume", ["--release-dir", temporary, "--verify-ops-access"])
            _, status = self.invoke(directory, "status")
            self.assertEqual(status["stages"]["ops_access"]["status"], "awaiting_input")

    def test_interrupted_or_unmaterializable_recheck_removes_stale_completion(self):
        for materialize_failure in (False, True):
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary).resolve() / "state"
                store = cli.CheckpointStore(directory, {**DISCOVERY, **RELEASE})
                with store.lock():
                    store.resume()
                    store.set_stage("infrastructure", "complete")
                    store.set_stage("ops_access", "complete")
                materialize = Mock(side_effect=ValueError("corrupt release") if materialize_failure else None)
                verify = Mock(side_effect=KeyboardInterrupt())
                bundle = types.SimpleNamespace(verify_release=lambda _: RELEASE, materialize_release=materialize)
                with patch.dict(sys.modules, {"installer_bundle": bundle, "installer_ops_verify": types.SimpleNamespace(verify_ops_access=verify)}), patch.object(cli, "discover", return_value=DISCOVERY), self.assertRaises(ValueError if materialize_failure else KeyboardInterrupt):
                    self.invoke(directory, "resume", ["--release-dir", temporary, "--verify-ops-access"])
                if materialize_failure:
                    verify.assert_not_called()
                _, status = self.invoke(directory, "status")
                self.assertEqual(status["stages"]["ops_access"]["status"], "awaiting_input")

    def test_ops_complete_requires_live_verifier_and_failed_recheck_downgrades(self):
        for failure in (False, True):
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary).resolve() / "state"
                store = cli.CheckpointStore(directory, {**DISCOVERY, **RELEASE})
                with store.lock():
                    store.resume()
                    store.set_stage("infrastructure", "complete")
                    store.set_stage("ops_access", "complete" if failure else "awaiting_input")
                bundle = types.SimpleNamespace(verify_release=lambda _: RELEASE, materialize_release=Mock(return_value=directory / "release"))
                verify = Mock(side_effect=cli.InfrastructureError("SSM offline") if failure else None)
                with patch.dict(sys.modules, {"installer_bundle": bundle, "installer_ops_verify": types.SimpleNamespace(verify_ops_access=verify)}), patch.object(cli, "discover", return_value=DISCOVERY):
                    if failure:
                        with self.assertRaises(cli.InfrastructureError):
                            self.invoke(directory, "resume", ["--release-dir", temporary, "--verify-ops-access"])
                    else:
                        _, result = self.invoke(directory, "resume", ["--release-dir", temporary, "--verify-ops-access"])
                        self.assertEqual(result["result"], "ops_access_ready")
                        self.assertFalse(result["deployment_complete"])
                verify.assert_called_once_with(directory / "release", directory, DISCOVERY, "test")
                _, status = self.invoke(directory, "status")
                self.assertEqual(status["stages"]["ops_access"]["status"], "awaiting_input" if failure else "complete")

    def test_ops_apply_requires_terminal_sha_and_separate_operation(self):
        for options in (["--apply-ops-access"], ["--plan-ops-access", "--apply-ops-access"], ["--ops-plan-sha", "a" * 64]):
            with patch.object(cli.sys.stdin, "isatty", return_value=False), patch.object(cli, "discover") as discover, self.assertRaises(cli.StateError):
                cli.run(["resume", "--state-dir", "/unused", *options])
            discover.assert_not_called()

    def test_ops_plan_and_apply_never_claim_session_ready(self):
        for operation in ("plan", "apply", "cancel", "failure"):
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary).resolve() / "state"
                store = cli.CheckpointStore(directory, {**DISCOVERY, **RELEASE})
                with store.lock():
                    store.resume()
                    store.set_stage("infrastructure", "complete")
                    store.set_stage("preflight", "complete")
                original = (directory / "checkpoint.json").read_bytes()
                bundle = types.SimpleNamespace(verify_release=lambda _: RELEASE, materialize_release=Mock(return_value=directory / "release"))
                execution = types.SimpleNamespace(plan_ops_access=Mock(return_value="a" * 64), apply_ops_access=Mock())
                options = ["--release-dir", temporary, "--plan-ops-access"] if operation == "plan" else ["--release-dir", temporary, "--apply-ops-access", "--ops-plan-sha", "a" * 64]
                confirmation = "APPLY SSM 123456789012 ap-northeast-1 test-node node-operator/ops-access/terraform.tfstate " + "a" * 64
                if operation == "failure":
                    execution.apply_ops_access.side_effect = cli.InfrastructureError("partial apply")
                with patch.dict(sys.modules, {"installer_bundle": bundle, "installer_ops_execution": execution}), patch.object(cli, "discover", return_value=DISCOVERY), patch.object(cli.sys.stdin, "isatty", return_value=True), patch("builtins.input", return_value="cancel" if operation == "cancel" else confirmation):
                    if operation in ("cancel", "failure"):
                        with self.assertRaises(cli.StateError if operation == "cancel" else cli.InfrastructureError):
                            self.invoke(directory, "resume", options)
                    else:
                        _, result = self.invoke(directory, "resume", options)
                        self.assertFalse(result["deployment_complete"])
                        self.assertEqual(result["result"], "ops_access_plan_ready" if operation == "plan" else "ops_access_provisioned")
                        self.assertEqual(result["ops_plan_sha256"], "a" * 64 if operation == "plan" else None)
                if operation == "cancel":
                    execution.apply_ops_access.assert_not_called()
                    self.assertEqual((directory / "checkpoint.json").read_bytes(), original)
                else:
                    _, status = self.invoke(directory, "status")
                    self.assertEqual(status["stages"]["preflight"]["status"], "complete")
                    self.assertEqual(status["stages"]["ops_access"]["status"], "failed" if operation == "failure" else "awaiting_input")

    def test_ops_preparation_is_separate_and_never_claims_access_ready(self):
        for infrastructure_status in ("pending", "complete"):
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary).resolve() / "state"
                store = cli.CheckpointStore(directory, {**DISCOVERY, **RELEASE})
                with store.lock():
                    store.resume()
                    store.set_stage("infrastructure", infrastructure_status)
                prepare = Mock()
                bundle = types.SimpleNamespace(verify_release=lambda _: RELEASE, materialize_release=Mock(return_value=directory / "release"))
                with patch.dict(sys.modules, {"installer_bundle": bundle, "installer_ops_access": types.SimpleNamespace(prepare_ops_access=prepare)}), patch.object(cli, "discover", return_value=DISCOVERY):
                    options = ["--release-dir", temporary, "--prepare-ops-access"]
                    if infrastructure_status == "pending":
                        with self.assertRaises(cli.StateError):
                            self.invoke(directory, "resume", options)
                        prepare.assert_not_called()
                        bundle.materialize_release.assert_not_called()
                    else:
                        _, result = self.invoke(directory, "resume", options)
                        prepare.assert_called_once_with(directory / "release", directory, DISCOVERY, "test")
                        self.assertEqual(result["result"], "ops_access_inputs_ready")
                        self.assertFalse(result["deployment_complete"])
                        _, status = self.invoke(directory, "status")
                        self.assertEqual(status["stages"]["ops_access"]["status"], "awaiting_input")
                        self.assertEqual(status["stages"]["infrastructure"]["status"], "complete")

    def test_ops_cannot_be_combined_with_infrastructure_or_start(self):
        for command, extra in (("start", []), ("resume", ["--apply-infrastructure"]), ("resume", ["--execution-profile", "other"])):
            with patch.object(cli, "discover") as discover, self.assertRaises(cli.StateError):
                cli.run([command, "--state-dir", "/unused", "--prepare-ops-access", *extra])
            discover.assert_not_called()

    def test_ops_preparation_cannot_reset_completed_access(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve() / "state"
            store = cli.CheckpointStore(directory, {**DISCOVERY, **RELEASE})
            with store.lock():
                store.resume()
                store.set_stage("infrastructure", "complete")
                store.set_stage("ops_access", "complete")
                store.set_stage("preflight", "complete")
            original = (directory / "checkpoint.json").read_bytes()
            materialize = Mock()
            bundle = types.SimpleNamespace(verify_release=lambda _: RELEASE, materialize_release=materialize)
            with patch.dict(sys.modules, {"installer_bundle": bundle}), patch.object(cli, "discover", return_value=DISCOVERY), self.assertRaises(cli.StateError):
                self.invoke(directory, "resume", ["--release-dir", temporary, "--prepare-ops-access"])
            materialize.assert_not_called()
            _, status = self.invoke(directory, "status")
            self.assertEqual(status["stages"]["ops_access"]["status"], "complete")
            self.assertEqual(status["stages"]["preflight"]["status"], "complete")
            self.assertEqual((directory / "checkpoint.json").read_bytes(), original)

    def test_failed_ops_preparation_preserves_checkpoint(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve() / "state"
            store = cli.CheckpointStore(directory, {**DISCOVERY, **RELEASE})
            with store.lock():
                store.resume()
                store.set_stage("infrastructure", "complete")
                store.set_stage("preflight", "complete")
            original = (directory / "checkpoint.json").read_bytes()
            bundle = types.SimpleNamespace(verify_release=lambda _: RELEASE, materialize_release=Mock())
            ops = types.SimpleNamespace(prepare_ops_access=Mock(side_effect=cli.InfrastructureError("context mismatch")))
            with patch.dict(sys.modules, {"installer_bundle": bundle, "installer_ops_access": ops}), patch.object(cli, "discover", return_value=DISCOVERY), self.assertRaises(cli.InfrastructureError):
                self.invoke(directory, "resume", ["--release-dir", temporary, "--prepare-ops-access"])
            self.assertEqual((directory / "checkpoint.json").read_bytes(), original)

    def test_apply_requires_terminal_before_any_discovery(self):
        with patch.object(cli.sys.stdin, "isatty", return_value=False), patch.object(cli, "discover") as discovery, self.assertRaises(cli.StateError):
            cli.run(["start", "--state-dir", "/unused", "--apply-infrastructure"])
        discovery.assert_not_called()

    def test_cancelled_confirmation_never_applies(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve() / "state"
            bundle = types.SimpleNamespace(verify_release=lambda _: RELEASE, materialize_release=Mock(return_value=directory / "release"))
            discovery = {**DISCOVERY, "availability_zones": ["ap-northeast-1a", "ap-northeast-1c"]}
            options = ["--release-dir", temporary, "--aws-profile", "test", "--aws-region", "ap-northeast-1", "--name", "test-node",
                       "--apply-infrastructure", "--backend-principal-arn", "arn:aws:iam::123456789012:role/backend"]
            with patch.dict(sys.modules, {"installer_bundle": bundle}), patch.object(cli, "discover", return_value=discovery), patch.object(cli, "verify_backend_role", return_value={}), patch.object(cli, "prepare_inputs"), patch.object(cli, "apply_infrastructure") as apply, patch.object(cli.sys.stdin, "isatty", return_value=True), patch("builtins.input", return_value="yes"), self.assertRaises(cli.StateError):
                self.invoke(directory, "start", options)
            apply.assert_not_called()
            _, status = self.invoke(directory, "status")
            self.assertEqual(status["stages"]["infrastructure"]["status"], "awaiting_input")

    def test_confirmed_apply_completes_only_infrastructure_and_failure_is_preserved(self):
        for outcome in (None, cli.InfrastructureError("partial apply")):
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary).resolve() / "state"
                bundle = types.SimpleNamespace(verify_release=lambda _: RELEASE, materialize_release=Mock(return_value=directory / "release"))
                discovery = {**DISCOVERY, "availability_zones": ["ap-northeast-1a", "ap-northeast-1c"]}
                options = ["--release-dir", temporary, "--aws-profile", "test", "--aws-region", "ap-northeast-1", "--name", "test-node",
                           "--apply-infrastructure", "--backend-principal-arn", "arn:aws:iam::123456789012:role/backend"]
                with patch.dict(sys.modules, {"installer_bundle": bundle}), patch.object(cli, "discover", return_value=discovery), patch.object(cli, "verify_backend_role", return_value={}), patch.object(cli, "prepare_inputs"), patch.object(cli, "apply_infrastructure", side_effect=outcome) as apply, patch.object(cli.sys.stdin, "isatty", return_value=True), patch("builtins.input", return_value="APPLY 123456789012 ap-northeast-1 test-node AUDIT ap-northeast-2"):
                    if outcome:
                        with self.assertRaises(cli.InfrastructureError):
                            self.invoke(directory, "start", options)
                    else:
                        _, result = self.invoke(directory, "start", options)
                        self.assertEqual(result["result"], "infrastructure_ready")
                        self.assertFalse(result["deployment_complete"])
                apply.assert_called_once()
                _, status = self.invoke(directory, "status")
                self.assertEqual(status["stages"]["infrastructure"]["status"], "failed" if outcome else "complete")
                self.assertEqual(status["stages"]["vault"]["status"], "pending")

    def invoke(self, directory, command, extra=()):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = cli.run([command, "--state-dir", str(directory), *extra])
        return result, json.loads(output.getvalue())

    def test_start_status_resume_and_context_binding(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(sys.modules, {"installer_bundle": types.SimpleNamespace(verify_release=lambda _: RELEASE)}), patch.object(cli, "discover", return_value=DISCOVERY) as discover:
            directory = Path(temporary) / "state"
            options = ["--release-dir", temporary, "--aws-profile", "test", "--aws-region", "ap-northeast-1", "--name", "test-node"]
            _, result = self.invoke(directory, "start", options)
            self.assertFalse(result["deployment_complete"])
            count = discover.call_count
            _, status = self.invoke(directory, "status")
            self.assertEqual(discover.call_count, count)
            self.assertEqual(status["stages"]["preflight"]["status"], "awaiting_input")
            self.invoke(directory, "resume", ["--release-dir", temporary])
            with self.assertRaises(cli.StateError):
                self.invoke(directory, "start", options)
            with patch.object(cli, "discover", return_value={**DISCOVERY, "aws_account_id": "999999999999"}), self.assertRaises(cli.StateError):
                self.invoke(directory, "resume", ["--release-dir", temporary])

    def test_running_stage_is_not_retried_or_completed(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(sys.modules, {"installer_bundle": types.SimpleNamespace(verify_release=lambda _: RELEASE)}), patch.object(cli, "discover", return_value=DISCOVERY):
            directory = Path(temporary) / "state"
            context = {**DISCOVERY, **RELEASE}
            store = cli.CheckpointStore(directory, context)
            with store.lock():
                store.resume()
                store.set_stage("infrastructure", "running")
            with self.assertRaises(cli.StateError):
                self.invoke(directory, "resume", ["--release-dir", temporary])
            with store.lock():
                self.assertEqual(store.resume()["stages"]["infrastructure"]["status"], "running")

    def test_invalid_release_never_queries_aws(self):
        def reject(_):
            raise ValueError("invalid release")
        with tempfile.TemporaryDirectory() as temporary, patch.dict(sys.modules, {"installer_bundle": types.SimpleNamespace(verify_release=reject)}), patch.object(cli, "discover") as discover:
            with self.assertRaises(ValueError):
                self.invoke(Path(temporary) / "state", "start", ["--release-dir", temporary])
            discover.assert_not_called()

    def test_prepare_materializes_context_bound_release_without_claiming_deployment(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve() / "state"
            materialize = Mock(return_value=directory / "release")
            bundle_module = types.SimpleNamespace(verify_release=lambda _: RELEASE, materialize_release=materialize)
            discovery = {**DISCOVERY, "availability_zones": ["ap-northeast-1a", "ap-northeast-1c"]}
            role = "arn:aws:iam::123456789012:role/backend"
            options = ["--release-dir", temporary, "--aws-profile", "test", "--aws-region", "ap-northeast-1", "--name", "test-node",
                       "--prepare-infrastructure", "--backend-principal-arn", role, "--execution-profile", "execution"]
            with patch.dict(sys.modules, {"installer_bundle": bundle_module}), patch.object(cli, "discover", return_value=discovery), patch.object(cli, "verify_backend_role", return_value={"existence": "verified"}) as verify_role, patch.object(cli, "verify_execution_profile", return_value={"session_identity": "verified"}) as execution, patch.object(cli, "bootstrap_permission_probe", return_value={"result": "requires_permission_review"}), patch.object(cli, "prepare_inputs") as prepare:
                _, result = self.invoke(directory, "start", options)
            verify_role.assert_called_once_with(discovery, role)
            execution.assert_called_once_with(discovery, discovery["backend_role"], "execution")
            materialize.assert_called_once_with(Path(temporary), directory / "release", RELEASE["release_sha"], RELEASE["bundle_digest"])
            prepare.assert_called_once_with(directory / "release", directory / "infrastructure-inputs", discovery, role)
            self.assertEqual(result["result"], "infrastructure_inputs_ready")
            self.assertFalse(result["deployment_complete"])
            _, status = self.invoke(directory, "status")
            self.assertEqual(status["stages"]["infrastructure"]["status"], "awaiting_input")

    def test_wrong_role_never_materializes_or_executes_release(self):
        with tempfile.TemporaryDirectory() as temporary:
            materialize = Mock()
            bundle_module = types.SimpleNamespace(verify_release=lambda _: RELEASE, materialize_release=materialize)
            discovery = {**DISCOVERY, "availability_zones": ["ap-northeast-1a", "ap-northeast-1c"]}
            options = ["--release-dir", temporary, "--aws-profile", "test", "--aws-region", "ap-northeast-1", "--name", "test-node",
                       "--prepare-infrastructure", "--backend-principal-arn", "arn:aws:iam::999999999999:role/backend"]
            with patch.dict(sys.modules, {"installer_bundle": bundle_module}), patch.object(cli, "discover", return_value=discovery), patch.object(cli, "prepare_inputs") as prepare, self.assertRaises(cli.InfrastructureError):
                self.invoke(Path(temporary).resolve() / "state", "start", options)
            materialize.assert_not_called()
            prepare.assert_not_called()

    def test_wrong_execution_profile_prevents_preparation(self):
        with tempfile.TemporaryDirectory() as temporary:
            materialize = Mock()
            bundle_module = types.SimpleNamespace(verify_release=lambda _: RELEASE, materialize_release=materialize)
            discovery = {**DISCOVERY, "availability_zones": ["ap-northeast-1a", "ap-northeast-1c"]}
            options = ["--release-dir", temporary, "--aws-profile", "test", "--aws-region", "ap-northeast-1", "--name", "test-node",
                       "--prepare-infrastructure", "--backend-principal-arn", "arn:aws:iam::123456789012:role/backend", "--execution-profile", "wrong"]
            with patch.dict(sys.modules, {"installer_bundle": bundle_module}), patch.object(cli, "discover", return_value=discovery), patch.object(cli, "verify_backend_role", return_value={}), patch.object(cli, "verify_execution_profile", side_effect=cli.PreflightError("wrong role")), patch.object(cli, "prepare_inputs") as prepare, self.assertRaises(cli.PreflightError):
                self.invoke(Path(temporary).resolve() / "state", "start", options)
            materialize.assert_not_called()
            prepare.assert_not_called()

    def test_unavailable_role_prevents_release_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            materialize = Mock()
            bundle_module = types.SimpleNamespace(verify_release=lambda _: RELEASE, materialize_release=materialize)
            discovery = {**DISCOVERY, "availability_zones": ["ap-northeast-1a", "ap-northeast-1c"]}
            options = ["--release-dir", temporary, "--aws-profile", "test", "--aws-region", "ap-northeast-1", "--name", "test-node",
                       "--prepare-infrastructure", "--backend-principal-arn", "arn:aws:iam::123456789012:role/missing"]
            with patch.dict(sys.modules, {"installer_bundle": bundle_module}), patch.object(cli, "discover", return_value=discovery), patch.object(cli, "verify_backend_role", side_effect=cli.PreflightError("unavailable")), patch.object(cli, "prepare_inputs") as prepare, self.assertRaises(cli.PreflightError):
                self.invoke(Path(temporary).resolve() / "state", "start", options)
            materialize.assert_not_called()
            prepare.assert_not_called()


if __name__ == "__main__":
    unittest.main()
