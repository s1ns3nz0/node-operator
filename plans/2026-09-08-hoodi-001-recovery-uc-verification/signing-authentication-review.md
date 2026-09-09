# Signing authentication compatibility review

Observed 2026-09-08; read-only upstream inspection. No credentials or live
resources changed. This is a design decision request, not acceptance evidence.

## Pinned-client evidence

Prysm v7.1.8 `NewApiClient` constructs its Web3Signer HTTP client using
`otelhttp.NewTransport(http.DefaultTransport)`. It does not load a client TLS
certificate in that constructor. The similarly named certificate/key flags
explicitly describe the gRPC remote signer, not this HTTP path. Adding those
flags to the current template would not establish HTTP mutual authentication.

Sources:
- https://github.com/OffchainLabs/prysm/blob/v7.1.8/validator/keymanager/remote-web3signer/internal/client.go
- https://github.com/OffchainLabs/prysm/blob/v7.1.8/cmd/validator/flags/flags.go
- https://docs.web3signer.consensys.io/how-to/configure-tls

Web3Signer documents client certificate allowlisting and states that
`tls-allow-any-client` cannot be combined with the known-clients option.
The current runtime explicitly allows any TLS client. Server CA verification
and NetworkPolicy are valuable but do not meet the existing mutually
authenticated, audience-bound request requirement.

## Recommended path, pending design approval

Keep the reviewed Prysm image unchanged. Add a loopback-only authentication
adapter in the exact validator Pod, with its own narrowly mounted transport
identity (never a validator BLS key). It connects through the existing
Lease-controlled passthrough fence to Web3Signer using a set-specific client
certificate and strict expected server SAN verification. Web3Signer must
allowlist only the intended certificate; remove allow-any-client. Bind the
adapter to the exact validator public-key signing path and intended upstream,
reject arbitrary destinations and redirects, and do not log request bodies.

The local Pod becomes the workload identity boundary, not a claim that the
Prysm process itself speaks mTLS. No credential may be shared across sets.
Credential issuance, limited lifetime, rotation, revocation and Secret/volume
delivery require review. The client still has no direct Vault access, no BLS
key, and no Lease write permission. This expands the current deployment and
transport credential lifecycle, so obtain explicit approval before building
or provisioning this path.

## Mandatory acceptance

Use synthetic keys and identities to test allowed requests and rejection of
missing, wrong-set, expired and revoked identities; wrong server names; wrong
validator key paths; and fence loss during existing connections. Exercise the
actual pinned Prysm image through the adapter. Verify all network bypasses are
denied in the cluster. Correlate real pre/post-recovery duties only after those
gates and custody review. No duty or UC completion follows from this review.
