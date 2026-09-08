# Trusted monitoring disposition

User resumed security completion and explicitly chose basic monitoring for
SSM. Preserve findings while binding CKV_AWS_126 acceptance to the exact ops
file, host address and check. Stage policy/collector before changing the module:
the pinned scanner embeds the collector and the gate trusts main policy.

Review and test this control-plane PR, obtain hosted admission, merge normally,
then verify/publish/promote its scanner through existing workflows. Only then
promote the separately reviewed SSM configuration and guarded migration.
No scanner135 exception, infrastructure mutation or state migration is included.
