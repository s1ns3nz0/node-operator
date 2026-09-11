#!/usr/bin/env python3
"""Narrow Vault transport for UC-5 configuration capture and exact role restore.

No KV endpoints, policy writes, bootstrap, retries, redirects or credential
issuance. The caller owns the maintenance guards and root-token lifecycle.
This module does not start a ceremony or modify anything when imported.
"""
import http.client
import importlib.util
import json
import pathlib
import re
import socket
import ssl

SPEC = importlib.util.spec_from_file_location(
    "uc5_role_state", pathlib.Path(__file__).with_name("uc5-runtime-role-state.py"))
STATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STATE)
ROLES = frozenset((STATE.RUNTIME_ROLE, STATE.DB_ROLE, STATE.CLIENT_ROLE))
POLICIES = frozenset((STATE.RUNTIME_POLICY, STATE.DB_POLICY, STATE.CLIENT_POLICY))
MAX_RESPONSE = 65536


class AdapterError(RuntimeError):
    """Only fixed messages leave the credential-bearing transport."""


class TunnelTransport:
    def __init__(self, address, ca_file, server_name, token):
        match = re.fullmatch(r"https://127\.0\.0\.1:(18200|18201)", address)
        if not match or server_name != "vault.vault.svc":
            raise AdapterError("reviewed private Vault tunnel required")
        if not isinstance(token, str) or not 1 <= len(token) <= 4096 or any(ord(c) < 33 or ord(c) > 126 for c in token):
            raise AdapterError("administrator credential shape invalid")
        if not isinstance(ca_file, (str, pathlib.Path)):
            raise AdapterError("explicit private Vault CA file required")
        ca_path = pathlib.Path(ca_file)
        if not ca_path.is_absolute() or ca_path.is_symlink() or not ca_path.is_file():
            raise AdapterError("private Vault CA must be an absolute regular non-symlink file")
        try:
            self.context = ssl.create_default_context(cafile=str(ca_path))
            self.context.minimum_version = ssl.TLSVersion.TLSv1_2
        except Exception:
            raise AdapterError("Vault CA initialization failed") from None
        self.port = int(match[1])
        self._token = token

    def close(self):
        # Drops this reference only; not secure memory erasure or token revocation.
        self._token = None

    def __call__(self, method, path, payload=None):
        if not ((method == "GET" and path in ROLES | POLICIES and payload is None) or
                (method == "POST" and path == STATE.RUNTIME_ROLE)):
            raise AdapterError("Vault operation outside UC-5 configuration boundary")
        if method == "POST":
            STATE._role(payload)
        if self._token is None:
            raise AdapterError("Vault transport is closed")
        connection = http.client.HTTPSConnection("vault.vault.svc", context=self.context, timeout=15)
        raw_socket = None
        try:
            raw_socket = socket.create_connection(("127.0.0.1", self.port), timeout=15)
            connection.sock = self.context.wrap_socket(raw_socket, server_hostname="vault.vault.svc")
            connection.request(method, "/v1/" + path,
                               body=None if payload is None else json.dumps(payload),
                               headers={"Content-Type": "application/json", "X-Vault-Token": self._token})
            response = connection.getresponse()
            status = response.status
            # Error bodies may contain sensitive details. Do not read or follow.
            if status != 200:
                return status, None
            raw = response.read(MAX_RESPONSE + 1)
            if len(raw) > MAX_RESPONSE:
                raise AdapterError("Vault response exceeds size limit")
            return status, json.loads(raw)
        except AdapterError:
            raise
        except Exception:
            # Never chain exception objects containing headers or raw responses.
            raise AdapterError("Vault configuration request failed") from None
        finally:
            connection.close()
            if raw_socket is not None:
                raw_socket.close()


class VaultAdapter:
    def __init__(self, transport):
        self.transport = transport

    def _read(self, path, allowed, optional=False):
        if path not in allowed:
            raise AdapterError("Vault read path is not allowlisted")
        status, response = self.transport("GET", path)
        # Only runtime role absence is expected after the later deletion step.
        if status == 404 and optional:
            return None
        if status != 200 or not isinstance(response, dict) or not isinstance(response.get("data"), dict):
            raise AdapterError("Vault configuration read did not succeed")
        return response["data"]

    def read_role(self, path):
        return self._read(path, ROLES, optional=path == STATE.RUNTIME_ROLE)

    def read_policy(self, path):
        value = self._read(path, POLICIES)
        if not isinstance(value.get("policy"), str) or not value["policy"]:
            raise AdapterError("Vault policy response malformed")
        return value["policy"]

    def write_role(self, path, value):
        if path != STATE.RUNTIME_ROLE:
            raise AdapterError("only the fixed runtime role may be restored")
        validated = STATE._role(value)
        status, _ = self.transport("POST", path, validated)
        if status != 204:
            raise AdapterError("runtime role write not acknowledged; readback required")
        # STATE.restore performs exact readback and non-target drift checks.
