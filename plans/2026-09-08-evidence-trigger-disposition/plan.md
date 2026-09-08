# Visible, expiring trigger disposition

Actual PR135 gate34215773302 blocked an existing inline Zizmor suppression in
the changed OPA workflow. Removing that comment locally exposes the actual
dangerous-triggers High/Medium finding. Do not hide it again or exempt all
workflows. Independent Sol-role review approved the exact path/rule/check
disposition with expiry2026-10-03 and documented residual risk.

First merge this policy-only prerequisite through current trusted-main policy
and exact-head review. Then PR135 removes the inline suppression and promotes
the already verified scanner. This PR does not change workflow execution,
scanner pins or infrastructure, and it does not itself remove the old comment.
