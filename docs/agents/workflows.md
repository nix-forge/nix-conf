# Matt Pocock workflows in this repository

Choose a workflow that matches the task. A small configuration edit can proceed
from the user's request to a focused check and review; it needs no interview,
specification ceremony, or new issue.

For substantial work across sessions or parallel writers, use
[coordination guidance](coordination.md). The optional user-managed
`engineering-workflow` skill supports task briefs and handoffs where installed.
The [harness integration guide](harnesses.md) describes the shared catalog,
specialist bundles, invocation controls and client-specific tool ownership.

The installed skill files are authoritative for their processes. Their upstream
text sometimes uses names such as `/research` or `/domain-modeling`. In this
installation those names have the `mattpocock-` prefix. Resolve the installed
skill by its full name and read its referenced files using the available skill
or filesystem tools; a tool literally named `Skill` is not required.

## Default skills

The shared default covers common tasks with one selected process per purpose:

| Task | Installed skill | Repository context |
| --- | --- | --- |
| Design a module's interface | `mattpocock-codebase-design` | Preserve module contracts and repository ownership. |
| Clarify terminology | `mattpocock-domain-modeling` | Follow [domain guidance](domain.md). |
| Diagnose a hard bug | `mattpocock-diagnosing-bugs` | Reproduce the actual symptom; follow repository test and publication policy. |
| Implement test-first | `mattpocock-tdd` | Agree the interface; use the repository's permitted test layer. |
| Review a fixed patch | `mattpocock-code-review` | Use the review inputs below; preserve the active harness's delegation rules. |
| Write a PR body | `mattpocock-pr` | Use reviewed evidence and the repository's publishing rules. |
| Research a question | `mattpocock-research` | Follow [research guidance](research.md), including for its background researcher. |
| Interview with durable domain docs | `mattpocock-grill-with-docs` | Explicit invocation; includes grilling and domain-modeling dependencies. |
| Interview without persistent docs | `mattpocock-grill-me` | Explicit invocation; includes grilling. |
| Run the interview primitive | `mattpocock-grilling` | Agents establish facts; users decide unresolved preferences. |
| Transfer a session | `mattpocock-handoff` | Explicit invocation; write a redacted handoff outside the repository. |
| Write agent instructions | `mattpocock-writing-for-agents` | Keep AGENTS.md short and disclose task-specific guidance through pointers. |

These skills supply task-specific processes. Ordinary small edits do not need
an interview, persistent spec, background researcher or delegated review unless
the chosen workflow and task call for them. Native harness and repository
instructions retain authority over tests, tool routing and external actions.

## Optional workflows

The [catalog research](../research/agent-skills-catalogs-research.md) inventories
all upstream skills. Add a stable Matt skill through
`programs.agent-skills.mattpocock.skills` when its process fits the task. This
replaces the default list. Include its dependencies: `grill-me` needs `grilling`;
`grill-with-docs` needs `grilling` and `domain-modeling`; controllers such as
`implement` and `ask-matt` refer to several other workflows. Read the chosen
skill and resolve its dependencies before selecting it. A referenced upstream
workflow is not necessarily installed.

Global routers and execution controllers (`ask-matt`, `implement`,
`implement-spec`, `wayfinder`) remain opt-in to keep process ownership clear.
Setup is a one-time operation, and tracker workflows require the
[tracker configuration](issue-tracker.md). Prototype, teaching, questionnaire,
retrospective and other specialist workflows stay available for explicit
selection. Experimental and miscellaneous skills remain outside the stable
selection.

The complete Superpowers plugin is an alternative opt-in workflow owner. Its
startup guidance, planning gates, TDD and delegation rules should be chosen as
a coherent process, with repository policy still authoritative. The shared
default does not enable it or its startup hooks. See the
[harness guide](harnesses.md) for the explicit alternative configuration.

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
