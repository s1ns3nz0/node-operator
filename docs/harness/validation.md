# Validation and admissibility

Run `npm run harness:check` for structural validation and `npm run
harness:verify` for the policy adapter. Each durable change records evidence.
Before completion, Terra records applicable checks; Sol integrates them and
requires an independent, clean-room debrief for non-trivial work.

On a new local environment, first run `npm run harness:bootstrap-policy-tools`.
It downloads repository-pinned OPA, Conftest, and ShellCheck binaries into the
ignored `.ci-tools/bin` directory after SHA-256 verification. The verify
command uses that directory ahead of the system `PATH`; it never downloads
tools implicitly.
