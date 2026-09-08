# Signer health proxy HTTP host correction

Root owns isolated source worktree `node-operator-dast-signer-host`, based on
frozen PR127 `cb4e002`. Files: DAST proxy manifest and its focused contract test.
No edits to PR127 or other agents' worktrees.

Observed: runtime signer allows HTTP host
`validator-hoodi-001-remote-signer.validator-operations.svc` (plus loopback).
The proxy uses the short name required by the current certificate CN for TLS,
and also sends that short name as HTTP Host; the latest probe returned 403.

Correction: preserve the short TLS connection/SNI hostname, public CA validation
and exact GET `/upcheck`, but explicitly send the existing allowed FQDN as the
HTTP Host. Do not widen the signer allowlist, bypass TLS, change certificates,
read keys, or expose signing endpoints. Keep all network policies unchanged.

Tests execute the actual embedded proxy with a mocked HTTPS connection and
assert distinct exact TLS/HTTP host identities, CA selection, GET-only route,
no response-body extraction, and rejection of signing/write paths. Obtain
independent Sol review before a scoped proxy-only rollout or a separate PR.
No runtime deployment is authorized merely by this contract.

## Reviewed rollout evidence

Source commit `4224883` was independently approved by the Sol integration owner
(two-file diff SHA256 `ac76c07e290cad93a365486aba952e59bce13cbf72a52aa69f429a27c4f960e7`).
The behavioral regression failed against the original proxy, then passed with
the exact HTTP Host correction. The unchanged Kyverno standalone suite was
explicitly skipped because its CLI was unavailable; no new Kyverno pass claimed.

The exact proxy Deployment argument was server-dry-run validated, then updated
using a JSON Patch `test` of the original source followed by a single `replace`.
Only the proxy code argument changed; no NetworkPolicy, signer or certificate
mutation occurred. Rollout succeeded. An owned local port-forward to that proxy
returned HTTP 200 for one fixed GET `/upcheck`; its upstream TLS verification
remained enabled. This diagnostic path is not evidence that the entire private
DAST Job or all four targets passed.
