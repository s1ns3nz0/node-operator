# Bounded DAST image compatibility diagnostic

Observed failure: fourth bounded scan run `1788851715`, exact merged GitOps
`7922fcf1497603d37f361ce65edc03c0f63c1481`, retained lifecycle `Error`, exit 137,
restart 0, exact approved image and no termination summary. This is not proof
of OOM or a DAST pass. Exact owned Job cleanup succeeded.

Sol proposed and root approved preparation of one no-target compatibility Job.
Execution requires root review of the exact prepared artifact before running.

- Owner: `/root/security_goal_ci_fallback`, primary Sol-role fallback.
- Files: private mode-700 diagnostic directory only, plus non-sensitive summary
  in this goal bundle. Do not change frozen source PR127 or other agents' files.
- One unique Job and label-scoped deny-all egress policy. Verify that the label
  does not match another allow-egress policy; Kubernetes policies are additive.
- Exact scanner digest, UID/GID 1000, token disabled, read-only root filesystem,
  current bounded CPU/memory and work/tmp/home writable mount layout.
- Shell-builtin fixed-schema checkpoint before each step, written to termination
  file so an untrappable kill may leave the previous checkpoint.
- Only executable presence booleans for jq/Python/curl/Java, fixed scratch-path
  write checks and `java -Xmx512m -version` exit status. Redirect its stdout and
  stderr to ephemeral files that are never retrieved.
- No ZAP daemon, network requests, Vault CA/Secret access, raw logs, arbitrary
  environment or filesystem extraction. Registry build history explicitly
  includes jq, curl, Python and Java; absence is not the current diagnosis.
- Retain only bounded checkpoint/lifecycle fields, fixed image identity and
  start/finish times. Capture exact Job/Pod and owned-policy cleanup results.
- No retry loop. Any further runtime change needs a new evidence-based review.

Passing this diagnostic does not complete requirement 4: actual per-target
passive DAST evidence remains required.
