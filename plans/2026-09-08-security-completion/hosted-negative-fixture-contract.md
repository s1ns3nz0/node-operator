# Hosted rejection proof

Requirement 3 explicitly includes a deliberately failing, non-sensitive
fixture. A missing human approval alone does not prove a scanner finding is
rejected. Prepare a separate draft PR from current main, never merge it.

The single candidate file is an inert JavaScript function containing
`eval('1 + 1')`, matched by the existing trusted `nodeoperator.no-eval` rule.
It must not be imported, executed, packaged into a release, deployed, or added
to any workflow. No secret-shaped values, credentials, network calls, policy
changes, exceptions or runtime infrastructure changes are allowed.

Terra may prepare the isolated local branch/file and verify the rule and
scanner collection path. Root reviews before push/draft PR. Capture hosted
trusted-gate subject SHA, nonzero `sast.semgrep` block and the exact-SHA failed
custom check. Ordinary workflow success alone is insufficient. Preserve the
evidence, then close the draft PR without merge. Do not alter frozen PR131.

If source-only scanner fixtures are excluded or the rule does not fire, report
the actual behavior; do not forge evidence or change the trusted rule.
