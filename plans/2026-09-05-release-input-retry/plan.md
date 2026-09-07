# Plan

1. Preserve conditional S3 creation with `If-None-Match: *`.
2. On a precondition collision, download the existing input and verify its exact expected file set plus bundle checksum, provenance, and buildspec.
3. Release using a new immutable tag after validation.
