# Matt Pocock workflows in this repository

Choose a workflow that matches the task. A small configuration edit can proceed
from the user's request to a focused check and review; it needs no interview,
specification ceremony, or new issue.

The installed skill files are authoritative for their processes. Their upstream
text sometimes uses names such as `/research` or `/domain-modeling`. In this
installation those names have the `mattpocock-` prefix. Resolve the installed
skill by its full name and read its referenced files using the available skill
or filesystem tools; a tool literally named `Skill` is not required.

## Choose a skill

| Task | Installed skill | Repository context |
| --- | --- | --- |
| Choose a workflow | `mattpocock-ask-matt` | Check this table against the router's larger upstream catalog. |
| Configure the skill conventions | `mattpocock-setup-matt-pocock-skills` | This setup is recorded in the tracker and domain guides. |
| Interview about a repository design | `mattpocock-grill-with-docs` | Use the glossary and real decisions; keep interview drafts local. |
| Interview without persistent domain docs | `mattpocock-grill-me` | Use for a stateless discussion. |
| Run the interview primitive | `mattpocock-grilling` | Resolve decisions with the user; find factual answers in the sources. |
| Clarify project terminology | `mattpocock-domain-modeling` | Read [domain guidance](domain.md). |
| Design a module's interface | `mattpocock-codebase-design` | Preserve the framework's module contracts and repository ownership. |
| Diagnose a hard bug or regression | `mattpocock-diagnosing-bugs` | Build a reproduction for the exact symptom; keep raw captures private. |
| Build requested behavior test-first | `mattpocock-tdd` | Agree the public interface to test, then work one behavior at a time. |
| Review against a fixed point | `mattpocock-code-review` | Use the standards and requirements sources below. |
| Investigate a source-backed question | `mattpocock-research` | Follow [research guidance](research.md), including for its background agent. |
| Resolve an in-progress merge or rebase | `mattpocock-resolving-merge-conflicts` | Trace each side's intent and keep unrelated work outside the operation. |
| Transfer work to a new environment | `mattpocock-handoff` | Write a redacted handoff outside the repository and link existing artifacts. |
| Guide steps only a human can perform | `mattpocock-wizard` | Use its installed template; keep one-off scripts and captured values private. |
| Write agent-facing instructions | `mattpocock-writing-for-agents` | Keep AGENTS.md short and put task-specific guidance behind clear pointers. |

The router, setup, two interview wrappers, and handoff are explicitly
user-invoked in the installed frontmatter. Mention their full names when
requesting them. The router also describes skills such as `implement`,
`to-spec`, `to-tickets`, `prototype`, and `wayfinder` that are not in this
installation. Do not promise those workflows are available. Their absence
does not prevent ordinary implementation from an agreed task.

## Review inputs

The standards source is [CONTRIBUTING.md](../../CONTRIBUTING.md), plus any
applicable nested instructions. The requirements source is the issue, supplied
spec, or user request identified through the [tracker guide](issue-tracker.md).
Keep standards and requirements findings separate, as the review skill requires.

Name the repository and resolve the base to a commit before reviewing. A
three-dot comparison with HEAD includes committed changes only. For a requested
working-tree review, capture the staged and unstaged patches and inspect new
files explicitly; do not claim a HEAD-only comparison reviewed those changes.
Review submodule changes in their own repositories as well as their root gitlinks.

## Completion

Use [CONTRIBUTING.md](../../CONTRIBUTING.md#validation) to select checks. Preserve
the user's agreed scope and any earlier agreement about test interfaces. A
helper agent receives the same requirements, repository boundaries, publication
rules, and expected output location as its parent task.

Finish with the implemented behavior, evidence from the relevant checks, and
any unresolved requirement. Promote only useful, redacted findings into public
docs. A skill workflow does not itself authorize deployment, history rewriting,
or communication with other people.
