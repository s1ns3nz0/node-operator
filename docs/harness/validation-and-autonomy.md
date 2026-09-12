# Validation and autonomy

## Verification ladder

Every change runs `npm run harness:verify` and therefore the applicable adapter
commands. A non-trivial task also
receives a fresh, context-independent review after implementation. High-risk
tasks add multi-lens review appropriate to the risk (for example security,
data migration, API compatibility, or reliability). Record commands and
outcomes in evidence; explain failures before changing direction.

Every durable artifact change also invokes `$admissibility-gate` before
completion, handoff, or commit. It invokes the pinned Paperthin `sip` route:
`shower` always; conditional `factchk`, `mandela`, and `detool`; audit-mode
`ssotize`; and `re0` for changed durable non-code artifacts. This is an artifact-quality
gate, not a replacement for `harness:verify`. Follow
`docs/admissibility-protocol.md` for its finding classification, one-correction
limit, `autobahn` descope behavior, and evidence requirements.

The primary Sol agent assigns the gate by role: Luna gathers the bounded
`factchk`/`mandela` evidence when applicable, Terra runs and records `sip` for
implementation changes, and Sol runs fresh-context `shower` at integration and
controls `autobahn`, ambiguity, and user-invoked `hate`. Workers cannot waive
required evidence. Missing role-owned evidence is an integration rejection,
not a silent not-applicable result.

CI executes the same harness configuration and adapter commands as local work.
CI is a verifier, not an alternate policy system.

## Behavioral proof

Before completion, invoke `$show-dont-tell` for a task that changes observable
behavior. Terra produces local proof matched to the boundary: a UI screenshot
or short video, API/CLI transcript, executable library example, or service
health and relevant logs. A bug fix demonstrates a reproducible before failure
and after success; a feature demonstrates its primary journey and key edge.

An independent reviewer receives only the contract's acceptance criteria and
the proof artifacts. Their plain-language assessment states what the evidence
proves, does not prove, and any gaps. Sol integrates that assessment. A purely
internal refactor may omit behavioral proof only with an evidence-backed,
independently assessed no-observable-change record. Keep the committed proof
compact; larger artifacts remain local unless the user approves committing
them. A user-visible demo blocks approval only when the task contract explicitly
marks it user-acceptance-gated.

## Ambiguity failures

For an ambiguous failure, use `$ambiguity-gate` and record contextual
Paperthin `readchk` evidence. A risk-adjacent case requires `autobahn` before
interview. One safe, reversible, evidence-based correction inside task
authority is allowed before asking the user; re-run the failed check and record
the result. A remaining material fork requires a primary Sol-owned `$grill-me`
interview and explicit user approval. Do not use repeated speculative fixes to
avoid escalation.

After approval, record the decision, reconcile sources with `ssotize`, and
update the product specification and task contract/plan. For an unresolved
fork, block only the affected work with the required decision.

Paperthin `hate` is not a routine validation gate. Run it only on an explicit
user invocation after a non-trivial plan forms and before an irreversible or
high-cost stage, or on direct request. It records one root objection and its
first-nail test.

## Authority boundary

Agents may inspect, edit, test, and commit only inside their assigned worktree
and file boundary. The primary agent alone integrates delegated work. These
actions require explicit task-level authorization: pull requests, merges,
deployments, publishing, secret changes, production access, payments, or
third-party messages. An authorized external action must be listed in the task
contract with target, purpose, and stopping condition.

The data boundary in `AGENTS.md` always applies. Never broaden access merely
because a task needs information; ask for the minimum missing authorization.
