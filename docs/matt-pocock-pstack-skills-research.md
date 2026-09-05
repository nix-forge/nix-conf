# Matt Pocock and PStack skills

## Recommendation

Use `pstack-unslop` on every piece of prose. It is a writing pass, not an engineering workflow. It asks Codex to keep the meaning and intended tone, then remove stock phrasing, vague claims, needless jargon, dense sentences, and obvious AI habits. The final self-audit is worth keeping. [Installed skill source](/Users/ianmh/.config/codex/skills/pstack-unslop/SKILL.md)

For work in Codex, choose a Matt Pocock skill by the job at hand:

| Job | Skill to use | Why it is a good fit |
| --- | --- | --- |
| A real bug, failure, or slowdown | `mattpocock-diagnosing-bugs` | It insists on a fast, deterministic, red-capable reproduction before guessing at a cause. |
| A user asks for test-first work | `mattpocock-tdd` | It keeps tests at agreed public seams and works one red-green behavior slice at a time. |
| Review a PR, branch, or WIP change from a known base | `mattpocock-code-review` | It separately checks repository standards and the originating spec. |
| Research that should leave durable evidence | `mattpocock-research` | It requires primary sources and writes cited findings into the repository. |
| Write a skill, `AGENTS.md`, `CLAUDE.md`, or agent-facing instructions | `mattpocock-writing-for-agents` | It is the right reference for triggers, completion criteria, progressive disclosure, and keeping instructions short enough to obey. |
| A person must complete dashboard, secret, account, or cutover steps | `mattpocock-wizard` | It produces a guided shell script for the human-only part of the job. |

The broadest high-value set for everyday coding is diagnosing bugs, TDD, formal review, and research. The wizard and agent-writing skills are excellent when their narrower trigger applies.

## Installed skills and boundaries

### `mattpocock-diagnosing-bugs`

Use this for explicit debugging or diagnosis, broken behavior, exceptions, test failures, performance regressions, and slowness. Its central constraint is unusually strict: build and run one reproduction that exercises the exact reported symptom and can fail before forming a theory. It must be fast, deterministic, and unattended. Then minimise the reproduction, make three to five ranked and falsifiable hypotheses, show them to the user, instrument only to distinguish those hypotheses, fix at a correct seam, and clean up debug work. Read `CONTEXT.md` and nearby ADRs when present. Redact secrets from all commands, outputs, and artifacts. This is the best debugging discipline here, but it is more process than a tiny, obvious fix needs. [Installed skill source](/Users/ianmh/.config/codex/skills/mattpocock-diagnosing-bugs/SKILL.md)

### `mattpocock-tdd`

Use only for test-first, red-green-refactor, or requested integration-test work. Before adding any test, Codex must get agreement on the public seams to test. Each cycle is one behavioral test, the smallest code to pass it, then the next behavior. Tests should use a public interface, draw expected values from an independent source, and avoid internal mocks. Mock system boundaries only. Refactoring belongs in the review stage, rather than the red-green loop. [Skill source](/Users/ianmh/.config/codex/skills/mattpocock-tdd/SKILL.md), [test examples](/Users/ianmh/.config/codex/skills/mattpocock-tdd/tests.md), and [mocking guidance](/Users/ianmh/.config/codex/skills/mattpocock-tdd/mocking.md).

### `mattpocock-code-review`

Use it for a review since a stated commit, branch, tag, or merge base. It first checks that the reference resolves and that the three-dot diff is nonempty. It then runs separate standards and spec reviews in parallel. The standards pass uses repository rules plus a Fowler-smell baseline, although the baseline is always a judgement call and repository rules win. The spec pass needs an issue or supplied/local spec. Keep the two reports separate rather than combining their severities. This is the right tool for a formal review, but not for a quick question about one file. It also requires `docs/agents/issue-tracker.md` to fetch issue references, otherwise it asks to run `/setup-matt-pocock-skills`. [Installed skill source](/Users/ianmh/.config/codex/skills/mattpocock-code-review/SKILL.md)

### `mattpocock-research`

Use it when research, API facts, documentation reading, or an evidence-backed recommendation deserves a file that survives the chat. It requires a background agent, primary sources, and one Markdown note with citations, placed where the repository keeps its research notes. This document follows that convention. [Installed skill source](/Users/ianmh/.config/codex/skills/mattpocock-research/SKILL.md)

### `mattpocock-writing-for-agents`

Use this whenever you create or edit a Codex skill, `AGENTS.md`, `CLAUDE.md`, or a document reached by one of those files. Its best idea is that an instruction's trigger wording decides whether an agent will ever read it. Keep trigger branches concrete; attach checkable, exhaustive completion criteria to steps; put optional reference material behind a clear pointer; and remove duplication, stale detail, and instructions that do not change behavior. For a skill, use model invocation only when automatic discovery or a shared reference pays for its always-loaded description. Otherwise make it user-invoked. [Skill source](/Users/ianmh/.config/codex/skills/mattpocock-writing-for-agents/SKILL.md) and [skill mechanics](/Users/ianmh/.config/codex/skills/mattpocock-writing-for-agents/SKILL-MECHANICS.md).

### `mattpocock-wizard`

Use this for procedures only a human can perform, such as browser dashboards, 2FA-protected account setup, credential entry, CI secret configuration, or a cutover. Do not use it for steps Codex can perform itself. It starts by mapping every manual stage, where each captured value goes, and which values are secret. Then it copies the packaged template and only writes the stages below the template marker. Each stage should name a real path through the UI, hide secret input, and pause before irreversible work. Syntax-check and statically trace the script, but do not run it end to end. Treat it as temporary unless a repeatable setup path merits committing. [Installed skill source](/Users/ianmh/.config/codex/skills/mattpocock-wizard/SKILL.md)

## Source scope

These findings cover the seven matching skills installed for this Codex session on 2026-09-01: six `mattpocock-*` skills and `pstack-unslop`. The local `SKILL.md` files and their linked references are the primary sources because they are the instructions this Codex installation actually uses.
