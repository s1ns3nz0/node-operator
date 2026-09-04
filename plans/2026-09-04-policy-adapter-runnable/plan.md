# Runnable policy adapter remediation

1. Reproduce every `harness:verify` adapter failure without touching cloud state.
2. Install the existing local development CLI dependencies only; retain CI's
   pinned policy-tool setup as the authoritative workflow path.
3. Add a synthetic malformed OSV collector envelope so normalizer failure is
   tested rather than caused by a missing file.
4. Mark literal Terraform/workflow fragments as intentional for ShellCheck.
5. Run the complete policy adapter and preserve only non-sensitive evidence.
