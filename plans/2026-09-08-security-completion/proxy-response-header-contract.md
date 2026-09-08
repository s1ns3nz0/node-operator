# Remove actual proxy server identification

Actual scan 1788855155 identifies passive rule 10036, risk 1, confidence 3.
The official rule concerns HTTP Server header identification:
https://www.zaproxy.org/docs/alerts/10036/

Source inspection finds both fixed DAST proxy handlers inherit Python's
default version-bearing Server response header. Root owns a narrow follow-up
inside PR131: override response-header emission to retain status and Date but
omit Server. Cover actual in-memory HTTP response serialization on success
and rejected/error requests. Existing GET-only, TLS identity/CA verification,
and P2P connect-close-without-application-bytes contracts must remain intact.

Do not filter captured headers, disable the passive rule, allow an alert,
change target selection, or claim which target produced the retained alert
without target-specific evidence. The code defect can be independently
reproduced locally; a reviewed deployment followed by a full scan is required
to prove it resolves the actual finding.

No runtime update is authorized by implementation alone. Require independent
review and exact Deployment-args-only dry-run/patch/readback before one scan.
