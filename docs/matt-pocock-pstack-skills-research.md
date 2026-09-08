# Installed Matt Pocock skills and repository setup

Reviewed: 2026-09-07. Scope: the installed Codex skills and this repository's
support for them. This replaces the earlier review of the smaller installed set.

## Findings

The local installation contains 15 Matt Pocock skills. Their names match the
selection in [the Codex module](../modules/home/dev/agentic-tui/codex.nix).
The installed package identifies itself as `unstable-2026-08-24`; the
[package source](../pkgs/pkgs/by-name/ma/mattpocock-skills/source.nix) records
upstream revision `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76`.

The [workflow guide](agents/workflows.md) lists all 15 and their intended use.
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
[tracker guide](agents/issue-tracker.md) defines both and keeps external messages
within the user's authorization. No issues or labels were created.

A single [glossary](../CONTEXT.md) supplies workstation terminology. The
[domain guide](agents/domain.md) keeps implementation guidance separate and
creates ADRs only when a real decision warrants one. The three Git submodules
remain separate ownership and validation scopes, described in
[CONTRIBUTING.md](../CONTRIBUTING.md).

The [research guide](agents/research.md) preserves existing document locations,
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
