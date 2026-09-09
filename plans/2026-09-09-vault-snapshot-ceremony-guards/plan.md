# Snapshot ceremony preparation

1. Fix premature success reporting and ignored revocation failure in the existing snapshot-only recovery wrapper.
2. Test only mocked Vault/snapshot commands, including operation failure and cleanup failure.
3. Independently review and integrate before asking user to run a fresh recovery-key ceremony. Never obtain shares in agent tools.
