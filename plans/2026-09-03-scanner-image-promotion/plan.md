# Scanner image promotion and deduplication

1. Pin CI to the currently published immutable scanner-image digest.
2. Calculate a stable hash from every Dockerfile input and attach it as an OCI label.
3. Have the release script compare that label on `:main` and skip an identical rebuild.
4. Push the labelled-image change, record its newly published digest, then pin CI to that final digest and confirm remote/local sync.
