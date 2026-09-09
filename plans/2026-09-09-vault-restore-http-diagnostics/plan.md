# Restore HTTP and diagnostics correction

1. Inspect failed-run cleanup metadata without secret/log access.
2. Reproduce HTTP double-getresponse against a real synthetic loopback server.
3. Fix response handling and add bounded stage/class diagnostics; regression-test real HTTP behavior and diagnostic redaction.
4. Independently review, pass CI, merge, and stage only the reviewed digest before user retry.

Observed: approved images present; no recovery containers, scratch directories or UID firewall jumps remain. This does not prove the precise failing phase or token revocation. Do not claim actual snapshot recovery succeeded.
