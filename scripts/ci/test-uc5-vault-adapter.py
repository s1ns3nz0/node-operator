#!/usr/bin/env python3
"""Offline configuration transport boundary tests; no credentials or sockets."""
import importlib.util
import pathlib
import tempfile
import unittest
from unittest import mock

PATH = pathlib.Path(__file__).resolve().parents[2] / "scripts/ops/lib/uc5-vault-adapter.py"
SPEC = importlib.util.spec_from_file_location("adapter", PATH)
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.response = (200, {"data": dict(M.STATE.EXPECTED_ROLE)})
        def transport(*args):
            self.calls.append(args)
            return self.response
        self.api = M.VaultAdapter(transport)

    def test_read_shape_and_absence(self):
        self.assertEqual(self.api.read_role(M.STATE.RUNTIME_ROLE), M.STATE.EXPECTED_ROLE)
        self.response = (404, None)
        self.assertIsNone(self.api.read_role(M.STATE.RUNTIME_ROLE))
        with self.assertRaises(M.AdapterError):
            self.api.read_role(M.STATE.DB_ROLE)
        for status in (301, 307, 403, 429, 500):
            self.response = (status, None)
            with self.assertRaises(M.AdapterError):
                self.api.read_role(M.STATE.RUNTIME_ROLE)

    def test_policy_and_malformed_data(self):
        self.response = (200, {"data": {"policy": "synthetic-policy"}})
        self.assertEqual(self.api.read_policy(M.STATE.DB_POLICY), "synthetic-policy")
        for body in ({"data": "bad"}, {"data": {}}, {}, "bad"):
            self.response = (200, body)
            with self.assertRaises(M.AdapterError):
                self.api.read_policy(M.STATE.DB_POLICY)

    def test_no_unrelated_operations(self):
        for path in ("sys/mounts", "node-operator-runtime/data/secret", M.STATE.DB_ROLE):
            with self.assertRaises(M.AdapterError):
                self.api.write_role(path, M.STATE.EXPECTED_ROLE)
        for path in ("sys/mounts", "node-operator-runtime/data/secret", M.STATE.DB_POLICY):
            with self.assertRaises(M.AdapterError):
                self.api.read_role(path)
        self.assertEqual(self.calls, [])

    def test_exact_role_write_only(self):
        self.response = (204, None)
        self.api.write_role(M.STATE.RUNTIME_ROLE, M.STATE.EXPECTED_ROLE)
        self.assertEqual(len(self.calls), 1)
        with self.assertRaises(M.STATE.StateError):
            self.api.write_role(M.STATE.RUNTIME_ROLE, dict(M.STATE.EXPECTED_ROLE, audience="other"))
        self.assertEqual(len(self.calls), 1)
        self.response = (403, None)
        with self.assertRaises(M.AdapterError):
            self.api.write_role(M.STATE.RUNTIME_ROLE, M.STATE.EXPECTED_ROLE)


class TransportTests(unittest.TestCase):
    def test_unsafe_configuration_does_not_create_tls_context(self):
        with mock.patch.object(M.ssl, "create_default_context") as context:
            for address, ca, name in (
                ("http://127.0.0.1:18200", None, "vault.vault.svc"),
                ("https://127.0.0.1:18200", None, "vault.vault.svc"),
                ("https://127.0.0.1:18200", "relative.crt", "vault.vault.svc"),
                ("https://external.example:18200", None, "vault.vault.svc"),
            ):
                with self.assertRaises(M.AdapterError):
                    M.TunnelTransport(address, ca, name, "synthetic")
            context.assert_not_called()

    def test_wire_boundary_and_response_limits(self):
        with tempfile.NamedTemporaryFile() as ca, \
                mock.patch.object(M.ssl, "create_default_context") as context, \
                mock.patch.object(M.socket, "create_connection") as connect, \
                mock.patch.object(M.http.client, "HTTPSConnection") as connection:
            wire = M.TunnelTransport("https://127.0.0.1:18200", ca.name, "vault.vault.svc", "synthetic")
            for method, path in (("DELETE", M.STATE.RUNTIME_ROLE), ("POST", M.STATE.DB_ROLE),
                                 ("GET", "node-operator-runtime/data/secret")):
                with self.assertRaises(M.AdapterError):
                    wire(method, path)
            connect.assert_not_called()
            response = connection.return_value.getresponse.return_value
            response.status = 307
            self.assertEqual(wire("GET", M.STATE.RUNTIME_ROLE), (307, None))
            response.read.assert_not_called()
            context.return_value.wrap_socket.assert_called_with(connect.return_value, server_hostname="vault.vault.svc")
            response.status = 200
            response.read.return_value = b"x" * (M.MAX_RESPONSE + 1)
            with self.assertRaises(M.AdapterError):
                wire("GET", M.STATE.RUNTIME_ROLE)
            response.read.assert_called_with(M.MAX_RESPONSE + 1)
            response.read.return_value = b"not-json"
            with self.assertRaises(M.AdapterError):
                wire("GET", M.STATE.RUNTIME_ROLE)
            wire.close()
            before = connect.call_count
            with self.assertRaises(M.AdapterError):
                wire("GET", M.STATE.RUNTIME_ROLE)
            self.assertEqual(connect.call_count, before)
            self.assertTrue(connection.return_value.close.called)


if __name__ == "__main__":
    unittest.main()
