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

## Superseded by verified eviction cause

The compatibility Job was prepared but **not executed**. A read-only query of
the exact previous Pod's retained events found Started at 07:15:19Z and
Evicted/Killing at 07:15:34Z. Root then separately authorized an in-memory
fixed-enum classifier of that exact Evicted event's message. No raw message was
returned or saved. Exact matching produced:

```json
{"kind":"emptydir-size-limit","volume":"temporary","limit":"16Mi"}
```

The format was independently verified against Kubernetes v1.35.0
[eviction helpers](https://github.com/kubernetes/kubernetes/blob/v1.35.0/pkg/kubelet/eviction/helpers.go)
and [emptyDir eviction logic](https://github.com/kubernetes/kubernetes/blob/v1.35.0/pkg/kubelet/eviction/eviction_manager.go).
This establishes the latest run's shared temporary-volume eviction cause; it
does not prove the causes of all earlier failures or a successful DAST scan.

The next bounded code proposal increases only that disk-backed scratch volume
to 512Mi, retains the 32Mi work volume, and declares a 512Mi ephemeral-storage
request with a 1Gi limit. These are explicit provisional capacity bounds, not a
claim of measured peak usage. Image, security context, network requests, TLS
verification and pass criteria must remain unchanged. Root independently
reviews the rendered resource bounds and regression tests before integration
and any one authorized runtime retry. Do not launch the superseded JVM Job.
