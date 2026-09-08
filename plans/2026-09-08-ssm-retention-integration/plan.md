# SSM retention integration

Preserve existing host and basic monitoring. Retained plans must preserve exact
nine-resource identities; fresh plans must enforce secure defaults. Publish only
after independent diff review and focused tests. Require actual hosted admission
and real approval before normal merge. No live apply in this code-integration
phase. Subsequent canonical-owner reconciliation and isolated S3 migration need
a fresh saved plan and independent review; a snapshot-copy plan is not authority.

The implementation was prepared under the parent security-completion contract.
This bundle records its final integration after prerequisites PR134-136 landed.

Independent review found that fresh-mode validation did not bound additional
non-instance resources. Before publication, Terra owns wrapper/test changes
to enforce allowed resources and actions with adversarial cases; Sol independently
reviews the fix. Root owns documentation and evidence. No live actions permitted.
