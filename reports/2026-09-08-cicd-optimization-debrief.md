# Clean-room debrief: CI/CD optimization

## Scope and method

Independent review of the completed task bundle, source CI/CD workflow and
script diff from `d00040a` through `c2f20c5`, focused local checks, and the
limited GitOps workflow/script diff from `origin/main..HEAD`. This debrief
does not cover deployment, publication, secrets, or production systems.

## Observed evidence

- Release invokes the integrity workflow through `workflow_call`; its manual
  `workflow_dispatch` entry point remains, but it no longer triggers
  separately on release tags. This avoids the prior duplicate tag execution.
- Grype `0.118.0` is downloaded from its versioned release URL and its archive
  SHA-256 is checked before extraction and execution.
- The integrity job scans the SBOM generated with the deterministic release
  bundle, rejects malformed scanner evidence, retains only a compact summary,
  and blocks critical, high, or unknown severities.
- The reusable job exports an approved artifact digest only after the SCA
  decision succeeds. Publication recomputes the rebuilt tar's SHA-256 and
  requires it to equal that approved digest; it also requires the regenerated
  SBOM's component version to equal that digest before signer input is sent.
- The scanned and published SBOM files are regenerated independently. Their
  bytes are not asserted identical; the artifact digest is the binding.
- Local checks passed: `test-release-sbom-sca.sh`, release reproducibility
  contract, `harness:check`, `harness:verify` (65 Rego tests, expected
  negative fixtures rejected), and whitespace checks.
- Hosted CI Release Integrity run `34179484345` passed in 1m21s, including
  deterministic builds, exact-SBOM SCA, evidence upload, decision enforcement,
  digest export, and integrity comparison/upload. The final code-CI set also
  passed: Terraform `34179482866`, quality `34179482908`, security
  `34179482875`, policy `34179482869`, and foundation `34179482915`.
- GitOps scoped review found `test-publish-oci-contract.sh` passing, including
  rejection of substituted source, subject digest, build type, builder, and
  nested-statement provenance. Its static publish serialization concurrency and
  cancelable per-ref reusable verification concurrency are present. GitOps run
  `34178913852` was reported successful.

## Findings

No unresolved blocking finding in the reviewed CI/CD diff. An initial finding
was that integrity scanned a reproducibility build while publication rebuilt a
separate artifact; the final diff resolves it with direct tar-byte digest
comparison and SBOM metadata binding.

Residual operational risk: scanner database freshness is runtime-dependent;
the compact evidence records database build metadata but does not pin a
database snapshot. This is an intentional availability/freshness tradeoff,
not a bypass of the fail-closed result validation.

## Conclusion

The reviewed change meets the task contract's fail-closed SCA, immutable tool,
reusable execution, compact-evidence, and artifact-provenance binding goals.
No deployment, publish, merge, secret, or production action was performed.
