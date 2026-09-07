# Vault validator audit ceremony

Enable `server.auditStorage` in the private GitOps Vault values before the
Vault upgrade. It creates a separate encrypted ReadWriteOnce audit PVC for
each Vault StatefulSet Pod at `/vault/audit`; it is not a Raft data volume.

After the Vault cluster is initialized, an approved administrator configures
two devices, never with `log_raw=true`:

```sh
vault audit enable -path=validator-file file \
  file_path=/vault/audit/validator-audit.json \
  log_raw=false hmac_accessor=false elide_list_responses=true

vault audit enable -path=validator-socket socket \
  address=unix:///vault/audit/validator-audit.sock \
  log_raw=false hmac_accessor=false elide_list_responses=true
```

The Unix socket must be bound by the separately reviewed local collector before
the second command. TCP/UDP audit sockets are prohibited because interruption
can lose records. Vault audit records are request/response pairs; downstream
deduplication joins them by `request.id`.

Run `verify-vault-validator-audit.sh` through the private Vault connection
afterward. A missing device, raw logging enabled, missing list-response elision,
or altered path is fail-closed for signer onboarding and validator duties.
