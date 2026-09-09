# Terminal prompt repair

1. Reproduce r+ open against a real PTY with no credentials.
2. Use a write-only terminal stream for getpass prompt output; getpass owns secure input.
3. Test real PTY opening and fail-closed echo fallback, independent review and normal PR gates.
4. Stage merged helper; user retains all recovery-share entry.
