# UC-1 through UC-5 review

| UC | Current result | Evidence | Required before final pass |
|---|---|---|---|
| UC-1 deposit | PASS for the existing deposit | Successful Hoodi receipt, exact canonical DepositEvent fields, matching SSZ roots, valid BLS proof, public and private pending-deposit records. | Preserve the evidence through the reviewed delivery path. Never make another deposit. |
| UC-2 key custody/signer | PARTIAL PASS | TLS-verified Web3Signer returned exactly the one intended public key; signer and retained slashing DB are Ready; no key or Vault secret was read. | With one live client, correlate an authenticated sign request and ensure no duplicate client exists. |
| UC-3 private Beacon | BLOCKED BY CHAIN PROCESSING | Private Prysm is synced, non-optimistic, EL-online and independently sees the exact pending deposit. The validator registry endpoint is correctly 404 while pending. | Wait for `active_ongoing`, then capture current/next assignments and an actual signed outcome. |
| UC-4 private duties | NOT YET RUNNABLE | The corrected observer validates current/next assignment APIs and never labels assignments as signatures. No validator client exists. | After safe activation, correlate client outcome, signer request, Beacon inclusion, and archived log request ID. |
| UC-5 revoke/restore | LIMITED PASS | The fenced role exercise failed closed, restored signer readiness, and has immutable Vault audit request/response correlation for role delete/create operations. | After a normal live duty, prove cached-key behavior and fail-closed enforcement under the reviewed fence, restore without root/recovery-token access, then prove a later duty. |

## Activation decision

Activation is denied now. The deposit is still in the consensus pending queue,
the existing Lease is expired, and the repository has no continuously renewing
fence controller. A one-time Lease patch would only make the timestamp look
fresh and would not enforce ongoing single-client ownership. The next runtime
change must therefore be a reviewed, continuously enforced fence plus an exact
zero-replica client render; scaling to one remains conditional on a fresh
`active_ongoing` record and every activation-gate check.
