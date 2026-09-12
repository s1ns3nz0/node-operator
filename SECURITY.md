# Security Policy

## Supported versions

Security fixes are applied to the latest commit on `main` and the most recent
published release. Older releases are not guaranteed to receive fixes.

## Reporting a vulnerability

Please do not open a public GitHub issue for a suspected vulnerability. Report
it privately through GitHub's **Report a vulnerability** action, or contact the
repository owner through a private channel with:

- a concise description and impact;
- affected commit, release, image digest, or workflow;
- reproducible steps or a minimal proof of concept; and
- any suggested mitigation.

Do not include credentials, recovery shares, validator keys, JWTs, Vault tokens,
or production data in a report. Redact sensitive evidence before sharing it.

We will acknowledge a report as soon as practical, validate the finding, and
coordinate a fix and disclosure timeline with the reporter. Automated scanner
findings should be filed as CI evidence unless they demonstrate an exploitable
security issue.

## Scope

This policy covers repository code, GitHub Actions workflows, release bundles,
container build definitions, Terraform, Helm/Kubernetes manifests, and the
validator signing-fence service.
