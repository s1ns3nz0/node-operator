# Signed verification evidence

1. Review pinned Cosign blob signing/verification interface and existing supply-chain controls.
2. Add opt-in signing job after all three read-only candidate verification jobs. Use only current run/attempt artifacts and exact main revision.
3. Build a deterministic verification statement after replaying narrow applicability checks, validating scanner freshness and binding every evidence file.
4. Keyless-sign the statement using GitHub OIDC; verify exact workflow identity/issuer/revision and semantic content. Preserve raw Unknown findings.
5. Test negative content/signature boundaries and real downloaded CI evidence. Independent review and scoped DevSecOps findings.
6. PR and merge before a separately requested opt-in hosted run. No claim of completed production signing or deployment from local tests.
