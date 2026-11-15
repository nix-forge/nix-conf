# Installed Matt Pocock skills and repository setup

Reviewed: 2026-09-07. Scope: the installed Codex skills and this repository's
support for them. This replaces the earlier review of the smaller installed set.

## Findings

The local installation contains 15 Matt Pocock skills. Their names match the
selection in [the Codex module](../../modules/home/dev/agentic-tui/codex.nix).
The installed package identifies itself as `unstable-2026-08-24`; the
[package source](../../pkgs/pkgs/by-name/ma/mattpocock-skills/source.nix) records
upstream revision `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76`.

The [workflow guide](../agents/workflows.md) lists all 15 and their intended use.
The router describes a larger upstream catalog, including implementation,
ticketing, prototype, and triage workflows that are not installed here.
Installing the router does not install those dependencies.

The setup skill expects a tracker guide and domain-document conventions under
`docs/agents/`. Those files were absent. The review skill expects documented
standards and a source of requirements; the repository had no root contribution
guide or glossary. The GitHub remote identifies `nix-forge/nix-conf`, and a
read-only repository query confirmed that GitHub Issues is enabled.

The skills already contain relevant privacy rules. Handoff explicitly saves
outside the workspace and redacts personal information. Diagnosis requires
redacted output. Research requires a cited note but leaves the repository to
choose its location and publication rules. A shared artifact policy is therefore
needed alongside the skill instructions.

## Setup implemented

The repository uses GitHub for published work items and ignored, redacted local
drafts for work that is not ready or authorized for publication. The
[tracker guide](../agents/issue-tracker.md) defines both and keeps external messages
within the user's authorization. No issues or labels were created.

A single [glossary](../../GLOSSARY.md) supplies workstation terminology. The
[domain guide](../agents/domain.md) keeps implementation guidance separate and
creates ADRs only when a real decision warrants one. The three Git submodules
remain separate ownership and validation scopes, described in
[CONTRIBUTING.md](../../CONTRIBUTING.md).

The [research guide](../agents/research.md) preserves existing document locations,
separates reusable findings from raw captures, and supplies a small template.
The workflow guide also distinguishes committed diffs from working-tree review
inputs, so an empty comparison with HEAD cannot stand in for reviewing new files.

AGENTS.md holds short, task-specific pointers to this guidance. Installed skill
files and their Nix package were left intact. `pstack-unslop` remains the prose
editing reference; it does not determine task scope or replace source checking.

## Primary sources and limits

All 15 installed `mattpocock-*/SKILL.md` files were read, along with setup's
tracker/domain templates, domain-modeling's glossary/ADR formats,
writing-for-agents' mechanics, and TDD's testing/mocking references. Installed
sources are under `$HOME/.config/codex/skills/`; these local files, rather than
upstream's moving main branch, define the reviewed behavior.

Repository facts were checked against the files linked above, AGENTS.md,
`flake/dev/`, `justfile`, `.gitmodules`, and the framework README. This review
establishes compatibility of the setup with the installed instructions. It does
not claim that every interactive skill workflow was exercised end to end.

## Research model policy retired, 2026-09-24

The [Codex module](../../modules/home/dev/agentic-tui/codex.nix) installs the
packaged `mattpocock-research` skill directly. It no longer appends a local
model-selection policy. The skill's upstream instructions determine its behavior,
subject to the user's instructions and the available agent controls.

## Catalog review, 2026-10-06

Question: which changes since the two `unstable-2026-09-04` package pins should
change the Codex and OpenCode skill selections? This is a source review, not a
live test of the workflows. The package recipes install each upstream catalog
under prefixed names; the two client modules select only [15 Matt Pocock
skills](../../modules/home/dev/agentic-tui/codex.nix) and `pstack-unslop` from
those packages. The OpenCode selection matches the Codex selection for these
two catalogs.

### Upstream changes

The previous Matt Pocock pin was
`3cca18b368ae95cdbdebbff572ccafa662551015`. As retrieved on
2026-10-06, upstream `main` was
[`6fd947921b935b7e1e69293a200400f0fdd5c15f`](https://github.com/mattpocock/skills/commit/6fd947921b935b7e1e69293a200400f0fdd5c15f),
68 commits ahead. The [pinned-to-current comparison](https://github.com/mattpocock/skills/compare/3cca18b368ae95cdbdebbff572ccafa662551015...6fd947921b935b7e1e69293a200400f0fdd5c15f)
shows 37 skill directories becoming 38: `implement-spec`, `pr`, `retro`, and
`chief-of-staff` appeared or moved into the catalog, while
`resolving-merge-conflicts` disappeared. The latest published release,
[v1.3.1 on 2026-10-04](https://github.com/mattpocock/skills/releases/tag/v1.3.1),
specifically graduates `implement-spec`, `pr`, and `retro` to Engineering and
retires `resolving-merge-conflicts` without a replacement. Its
[`24fe0ef7737efae15c87225755e9f6f5965e4888`](https://github.com/mattpocock/skills/commit/24fe0ef7737efae15c87225755e9f6f5965e4888)
source precedes the `chief-of-staff` addition on `main`. The [package updater](../../pkgs/pkgs/by-name/ma/mattpocock-skills/update.py)
tracks `main`, so this update pins the reviewed `6fd9479` commit while selecting
only the appropriate released workflows for the clients.

That release also changes the domain-document convention from `CONTEXT.md` to
`GLOSSARY.md`. The [new domain-modeling skill](https://github.com/mattpocock/skills/blob/24fe0ef7737efae15c87225755e9f6f5965e4888/skills/engineering/domain-modeling/SKILL.md)
and other updated skills look for `GLOSSARY.md`. At the start of this review,
this repository used `CONTEXT.md`. The package update therefore needs the
coordinated rename to [`GLOSSARY.md`](../../GLOSSARY.md) and updates to its
references, or the skills can miss the existing terminology. The upstream
release recommends `git mv` for existing glossaries. This is an integration
constraint, not a reason to silently rewrite the catalog's skill text.

The [pstack source pin](../../pkgs/pkgs/by-name/ps/pstack-skills/source.nix) is
`93b00b89ef425a9c1bac0d0b317dfc49c930ac99`. On 2026-10-06 upstream
`main` was
[`df581122cde17e6e27686b5a448bde23e4ad4318`](https://github.com/cursor/plugins/commit/df581122cde17e6e27686b5a448bde23e4ad4318),
180 commits ahead. The [pstack comparison](https://github.com/cursor/plugins/compare/93b00b89ef425a9c1bac0d0b317dfc49c930ac99...df581122cde17e6e27686b5a448bde23e4ad4318)
shows 45 skill directories becoming 51. The six additions are
`benchmark-checklist`, `correct`, `poteto-help`, `principle-attack-the-premise`,
`principle-explain-the-number`, and `principle-test-behavior-not-implementation`.
The selected [unslop skill](https://github.com/cursor/plugins/blob/df581122cde17e6e27686b5a448bde23e4ad4318/pstack/skills/unslop/SKILL.md)
remains present; its edit narrows the instruction to removing AI patterns and
removes its separate "adding soul" step.

### Selection decision

| Skill | Decision for both clients | Reason |
| --- | --- | --- |
| `mattpocock-pr` | Add with this source update. | The [new skill](https://github.com/mattpocock/skills/blob/6fd947921b935b7e1e69293a200400f0fdd5c15f/skills/engineering/pr/SKILL.md) gives PR bodies a compact summary, before/after evidence, and a merge-risk assessment. It complements the installed `code-review` workflow and this repository's review guidance. |
| `mattpocock-resolving-merge-conflicts` | Remove when updating the pin. | Upstream deleted its source and says ordinary conflict resolution needs no dedicated skill. The repository's [workflow guidance](../agents/workflows.md) can retain its conflict-handling advice without advertising an unavailable skill. |
| `mattpocock-implement-spec`, `mattpocock-retro`, `mattpocock-chief-of-staff` | Do not select by default. | [`implement-spec`](https://github.com/mattpocock/skills/blob/6fd947921b935b7e1e69293a200400f0fdd5c15f/skills/engineering/implement-spec/SKILL.md) assumes a spec, linked tickets, parallel implementers, worktree merges, and an integration branch. [`retro`](https://github.com/mattpocock/skills/blob/6fd947921b935b7e1e69293a200400f0fdd5c15f/skills/engineering/retro/SKILL.md) is a user-invoked environment review and would overlap this repository's existing agent guidance. [`chief-of-staff`](https://github.com/mattpocock/skills/blob/6fd947921b935b7e1e69293a200400f0fdd5c15f/skills/in-progress/chief-of-staff/SKILL.md) remains in `in-progress`. The package contains these skills, but neither client selects them. Add any of them for a concrete matching workflow, after reviewing its assumptions. |
| New pstack skills | Keep only `pstack-unslop` selected. | [`poteto-help`](https://github.com/cursor/plugins/blob/df581122cde17e6e27686b5a448bde23e4ad4318/pstack/skills/poteto-help/SKILL.md) routes the pstack suite and is Cursor-oriented; [`benchmark-checklist`](https://github.com/cursor/plugins/blob/df581122cde17e6e27686b5a448bde23e4ad4318/pstack/skills/benchmark-checklist/SKILL.md) and [`correct`](https://github.com/cursor/plugins/blob/df581122cde17e6e27686b5a448bde23e4ad4318/pstack/skills/correct/SKILL.md) fit narrower requested work. The three new principles are supporting material, not necessary standalone defaults. |

These are selection recommendations from inspected source text and the existing
repository conventions. They do not establish that the new package revisions
build on every declared platform, that the home profiles have activated them,
or that any workflow has been exercised in Codex or OpenCode. The upstream
branches can move after the revisions recorded here.

### Local verification

The v1.3.1 release package built on x86_64-linux, including its install check,
and the package repository's `just check` passed its all-systems evaluation at
that revision. The final `main` pin matches the package updater's dry run, and
all 15 selected Matt Pocock names exist in its source. Evaluation of the desktop
NixOS and MacBook Darwin home profiles at the release revision found
`mattpocock-pr` in both Codex and OpenCode selections and did not find
`mattpocock-resolving-merge-conflicts`. Nix formatting, whitespace, and local
Markdown links passed for the changed files. The final pin's package build and
home evaluation queued behind another desktop build and were canceled before
running. Darwin package building, home activation, and live skill invocation
remain untested.
