# Installer E2E scope

- Status: accepted through the user's sequential grill-me confirmations.
- Owner: root (Astra planning, user-approved model override).
- Product specification: [Installer E2E duty](../product-specs/installer-e2e-duty.md).

## Accepted outcome

The user excluded all UC-1 through UC-5 exercises. The replacement outcome is installation from a newly published release followed by verified validator duties, not a use-case campaign. The specification records the accepted start conditions, recovery rules, ceremony choices, activation approval and success criteria.

The user accepted a fresh node-operator deployment in Seoul, preservation of unrelated resources and custody/slashing records, same-state recovery without automatic destructive restart, blocking signing when slashing history cannot be safely recovered, new Vault recovery configuration of 3-of-5 with private file delivery and backup confirmation, explicit ACTIVATE, three consecutive epochs with finalized attestations, and a new immutable release based on v0.1.20 rather than retagging it.

## Authorization

This interview authorizes the revised task definition. It does not execute or independently authorize immediate cloud deletion, production access, publication, merge, secret access or validator activation. Obtain task-level execution authorization before those stages. Wallet transactions and secret ceremonies remain user-controlled.

## Relationship to prior work

[Preflight and resume](2026-09-13-installer-preflight-resume.md) and [Vault artifact authority](2026-09-13-vault-artifact-authority.md) remain prerequisites. Prior UC results are historical, not acceptance evidence for this new deployment. No historical files are deleted by this decision.
