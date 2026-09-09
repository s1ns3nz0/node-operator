# Raft directory startup repair

1. Reproduce using pinned old image, hardened options, empty data and no initialization.
2. Prepare both data and data/raft with private mode and dedicated UID/GID.
3. Test real filesystem layout, repeat empty-server startup, independent review and normal PR gates.
4. Stage only after merge; real recovery remains user-interactive.
