# Domain documentation

This repository uses one [root glossary](../../CONTEXT.md). Read its relevant
terms when exploring a domain, diagnosing a bug, designing a feature, or naming
tests. Implementation layout and module contracts belong in
[CONTRIBUTING.md](../../CONTRIBUTING.md), not in the glossary.

When terminology is resolved, use `mattpocock-domain-modeling` and update the
glossary with a short definition. Check that the code supports the definition.
Record unresolved questions in the task's draft rather than presenting an
assumption as settled language.

Read relevant architectural decisions under `docs/adr/` when that directory
exists. Create it with the first warranted decision, using `0001-slug.md` and
the next available number thereafter. An ADR is a short account of a real choice
and its reason. Record one only when reversal is costly, the choice would
surprise a future maintainer, and there was a meaningful trade-off.

Missing ADRs are normal. Continue with the code and existing task requirements;
avoid manufacturing decisions just to fill the layout. Identify conflicts with
an existing ADR explicitly when proposing a change.

The submodules have their own ownership and documentation. Consult those when
working inside them; their presence alone does not require a root
`CONTEXT-MAP.md`. Follow the [publication policy](../publication.md) for glossary
and decision updates as well as ordinary research notes.
