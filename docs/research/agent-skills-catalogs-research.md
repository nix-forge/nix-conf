# Matt Pocock skills: upstream inventory and integration

Reviewed 2026-11-16. The question is how to expose the complete upstream catalog through a reproducible Home Manager installation while keeping native harness configuration authoritative.

## Source and version

Upstream HEAD is [`5863806dd4e15c63174bee4e7515a4256792ecfa`](https://github.com/mattpocock/skills/commit/5863806dd4e15c63174bee4e7515a4256792ecfa), dated 2026-11-12. The existing `mattpocock-skills` package already pins this revision. The latest [release is v1.3.2](https://github.com/mattpocock/skills/releases/tag/v1.3.2), published 2026-10-29. HEAD retains manifest version 1.3.2 but includes changes after that release. These facts were checked against a fresh upstream clone and the GitHub releases API.

There are 39 upstream `SKILL.md` files. The [native plugin manifest](https://github.com/mattpocock/skills/blob/5863806dd4e15c63174bee4e7515a4256792ecfa/.claude-plugin/plugin.json) selects 27: all 20 engineering and seven productivity skills. Eight in-progress and four miscellaneous skills remain outside that manifest. The existing Nix package exports all 39 as `mattpocock-*`, preserving each skill's supporting files.

## Engineering inventory

The following skills live under [skills/engineering](https://github.com/mattpocock/skills/tree/5863806dd4e15c63174bee4e7515a4256792ecfa/skills/engineering).

| Skill | Behavior and integration considerations |
| --- | --- |
| `ask-matt` | Explicitly invoked router over the whole engineering flow. Reads a target skill before recommending it; phase-boundary reference distinguishes continuing, clearing, handing off, delegating and compacting. |
| `code-review` | Fresh-context parallel Standards and Spec reviews against a fixed base. Requires standards and requirements sources. Its example three-dot HEAD diff excludes uncommitted changes, so working-tree reviews need explicit patch capture. |
| `codebase-design` | Shared deep-module vocabulary: interface, seam, adapter, leverage and locality. Supporting references cover dependency-sensitive deepening and comparing alternative interfaces. |
| `diagnosing-bugs` | Requires a precise failing signal before hypotheses, minimizes the repro, ranks predictions, instruments deliberately and verifies a fix. Includes a human-feedback-loop script template. |
| `domain-modeling` | Sharpens canonical terminology in glossaries and records selective ADRs; consumes existing domain conventions. |
| `grill-with-docs` | Explicit wrapper around grilling plus domain-modeling. Its body depends on resolving those two skills. |
| `implement` | Explicit ticket/spec implementation wrapper over TDD and review, followed by a commit. Repository instructions still control test and commit scope. |
| `implement-spec` | Explicit task-graph coordinator: separate implementation worktrees, integration branch, mergers and final review. Requires compatible delegation, tracker configuration and substantial work. |
| `improve-codebase-architecture` | Explicit architectural survey with an HTML report, then an interview about a selected deepening opportunity. Depends on codebase-design vocabulary. |
| `pr` | Shapes concise PR bodies with evidence, a useful visual and a reversibility assessment. It guides writing and does not itself authorize publication. |
| `prototype` | Answers one logic/state or UI question with throwaway code. Supporting references distinguish a self-contained interactive logic demo from several UI variants. Captures the prototype separately as evidence. |
| `research` | Delegates primary-source investigation to a fresh background researcher and requests one cited Markdown note. Repository publication policy governs storage and review. |
| `retro` | Explicit session retrospective targeting navigation, checks, standards, instruction quality and tool economy. Presents improvement candidates. |
| `setup-matt-pocock-skills` | Explicit interactive setup for tracker, triage labels and domain documentation. Existing setup should be reused; invoking setup can edit instructions and create labels. |
| `tdd` | One red/green vertical slice at agreed public seams. Supporting references explain behavior-focused tests and mocks. Repository test policy takes precedence. |
| `to-spec` | Explicit synthesis of an existing conversation into a tracker spec, including testing decisions. Requires tracker setup and agreed test seams. |
| `to-tickets` | Explicit tracer-bullet breakdown with blocking edges. The user reviews granularity before publication. Native dependencies are preferred to prose links. |
| `triage` | Explicit issue/external-PR state machine, claim verification and durable briefs. Requires tracker/label conventions and can publish comments or close issues when authorized. |
| `wayfinder` | Explicit large-effort decision map with claimed child tickets and a dependency frontier. Resolves decisions before handing off to implementation. Includes research delegation and tracker writes. |
| `wizard` | Produces an interactive Bash procedure for steps only a human can perform. Supporting template supplies staged prompts and secret handling. Installation of this skill does not execute a wizard. |

## Productivity inventory

These seven skills live under [skills/productivity](https://github.com/mattpocock/skills/tree/5863806dd4e15c63174bee4e7515a4256792ecfa/skills/productivity).

| Skill | Behavior and integration considerations |
| --- | --- |
| `grill-me` | Explicit stateless wrapper around grilling. |
| `grilling` | Interviews through rounds of currently answerable questions. Agents find facts; users decide. Completion requires shared understanding. |
| `handoff` | Explicit portable redacted handoff in OS temporary storage outside the workspace. |
| `teach` | Explicit stateful learning workspace with mission, cited resources, learning records and reusable interactive components. |
| `to-questionnaire` | Explicit interview about recipient and desired information, followed by a questionnaire for someone else to answer. |
| `wait-what` | Explicit request to re-explain the previous message with context and plain language. |
| `writing-for-agents` | Reference for progressive disclosure, trigger wording and completion criteria. `SKILL-MECHANICS.md` covers model versus user invocation. |

## Experimental inventory

The eight [in-progress skills](https://github.com/mattpocock/skills/tree/5863806dd4e15c63174bee4e7515a4256792ecfa/skills/in-progress) are available in the package but excluded from the native plugin. Each is explicitly invoked upstream.

| Skill | Behavior and reason for separate selection |
| --- | --- |
| `chief-of-staff` | Long-running goal coordinator using subagents and a historical wiki. Assumes persistent orchestration and optional schedules. Direct sibling references such as `../retro/SKILL.md` break when directories are independently renamed `mattpocock-*`. |
| `claude-handoff` | Starts a named background Claude CLI agent from a temporary handoff. Depends on Claude-specific CLI semantics and can conflict with an enclosing harness's delegation rules. |
| `loop-me` | Interviews about recurring work and writes workflow specs plus notes about the user's world. It does not mandate AI, schedules or checkpoints. |
| `setup-ts-deep-modules` | Installs dependency-cruiser and entry-point boundary rules in a TypeScript project, scaffolds an example and proves a deliberate violation fails. Specific to JS tooling and repository package conventions. |
| `software-factory` | Design vocabulary for ephemeral agent runs, ticket trackers, Git hosts and orchestrators. Supporting files cover tasks and service choices. It describes a factory rather than implementing one. |
| `writing-beats` | Shapes fixed raw material one conceptual beat at a time, with explicit grounding and user choice. |
| `writing-fragments` | Exploratory raw-material collection; appends fragments after rereading to preserve user edits. |
| `writing-shape` | Shapes fixed material into an article paragraph by paragraph, settling reader prerequisites and preserving source material. |

## Miscellaneous inventory

The four [miscellaneous skills](https://github.com/mattpocock/skills/tree/5863806dd4e15c63174bee4e7515a4256792ecfa/skills/misc) are outside the native plugin.

| Skill | Behavior and reason for separate selection |
| --- | --- |
| `git-guardrails-claude-code` | Sets up a Claude PreToolUse hook for dangerous Git commands. Suggested installation writes Claude settings; Home Manager ownership must be respected. |
| `migrate-to-shoehorn` | Migrates TypeScript test-data assertions to partial-data helpers. Suggested package-manager commands are subject to repository dependency policy. |
| `scaffold-exercises` | Scaffolds numbered course exercises and validates with the ai-hero-cli. Its directory and tooling assumptions are course-specific. |
| `setup-pre-commit` | Sets up Husky and lint-staged in a JS project, then commits. It must not replace an existing Nix-managed hook owner without a deliberate migration. |

## Installation design

The [upstream README](https://github.com/mattpocock/skills/blob/5863806dd4e15c63174bee4e7515a4256792ecfa/README.md) now recommends native plugins for Claude Code, Codex and Copilot, direct skills installation for Gemini CLI, and the skills installer for other clients. It explicitly warns against installing both native plugins and editable skill copies in the same agent because every skill appears twice.

A declarative implementation can use the pinned package's original source for native plugins and its flattened skill output for clients with native skill-directory support. Source acquisition, selection and harness adapters should have separate ownership. The official plugin defines the 27 stable candidates; local defaults should select only complementary skills. Experimental and miscellaneous skills need explicit optional selection. Preserve whole directories, including templates, scripts, agent metadata and references.

The existing package rewrites frontmatter names while upstream text still refers to `/tdd` and the `Skill` tool with `tdd`. Provide one portable name-resolution instruction for flattened clients: resolve upstream names to the installed `mattpocock-*` names and read the appropriate skill through available tools. No literal tool named `Skill` should be required. Native plugins should retain upstream names and paths intact.

Keep model/user invocation metadata. Claude frontmatter and Codex `agents/openai.yaml` are distinct mechanisms; generic copying cannot promise universal explicit-only enforcement. Do not inject workflow bodies globally. Discovery should make workflows available, while invocation runs the chosen process. Installing the catalog does not execute its setup skills, install suggested hooks, create issues, start schedules or grant external-write authority.

## Limits

All 39 SKILL.md files and important references were inspected. This was read-only upstream and package-source analysis. No client activation, runtime discovery test or system build was performed. Current repository instructions, permissions, test policy, tracker setup and publication rules remain authoritative over upstream examples.

## Superpowers upstream research

Reviewed 2026-11-16. Upstream [obra/superpowers](https://github.com/obra/superpowers)
HEAD and latest release are **v7.0.2**, published 2026-11-03, at
[`22f0b463e7a5e579904dd6211a520321035526f7`](https://github.com/obra/superpowers/commit/22f0b463e7a5e579904dd6211a520321035526f7).
The annotated tag object is c62ffea8267a70de07583e153544d355b6748a56; it peels to
that commit. GitHub's latest-release API and `git ls-remote` agreed. License: MIT.
All fifteen current SKILL.md files were read, together with manifests, startup
hook, OpenCode implementation and installation documents.

## Complete skill inventory

Names below identify directories under the pinned
[skills tree](https://github.com/obra/superpowers/tree/22f0b463e7a5e579904dd6211a520321035526f7/skills).

| Skill | Analysis |
| --- | --- |
| brainstorming | Establishes intent and approaches before implementation, with design approval and then writing-plans. Clear small requests, an approved spike and opting out have explicit exceptions. Includes optional Node visual companion. |
| diagnosing-superpowers | Investigates session failures through seven parallel transcript analysis dimensions. Keeps sessions read-only and requires scrub/approval gates for exports and issue creation. Specialist diagnostic tool, not startup guidance. |
| dispatching-parallel-agents | Fans independent investigations into focused isolated contexts and integrates findings. Requires native delegation; unsuitable for shared state or dependent work. |
| executing-plans | Implements tasks in current context with durable task ledger, task-start/task-done helpers, TDD and one final independent review. Current inline alternative, replacing the historic batch/checkpoint workflow. |
| finishing-a-development-branch | Verifies branch then offers merge, push/create PR or preserve. Recognizes externally managed workspaces and detached HEAD. Discard requires explicit user request. |
| receiving-code-review | Checks review claims against code and requirements before implementing. Rejects unexamined agreement and prioritizes blocking fixes. |
| requesting-code-review | Sends fresh reviewer a diff range and requirements. Bundled reviewer template is a required supporting file. |
| subagent-driven-development | Fresh implementer and scoped reviewer per task, durable ledger, bounded fix loops and final whole-branch review. Shell helpers and sibling references are dependencies. Actual harness capabilities constrain tool/model choices. |
| systematic-debugging | Root-cause investigation, pattern comparison, one hypothesis, implementation and verification. Includes tracing, defense in depth, waiting and pollution-search helper. Repository event-driven wait rules override its polling examples. |
| test-driven-development | Observable RED/GREEN/refactor for behavior changes. Its broad new-test requirement conflicts with this repository's restricted test policy; repository instructions take precedence. |
| using-git-worktrees | Detects existing isolation and submodules, prefers native workspace tools, then Git. Generic dependency-install commands conflict with repository Nix-only tooling rules. |
| using-superpowers | Controller bootstrap and skill router; excludes delegated children. Loads platform references and requests workflows before actions. Explicitly gives user/repository instructions precedence. |
| verification-before-completion | Requires fresh command evidence before correctness/completion/passing claims. Evaluation, build, activation and runtime evidence remain distinct. |
| writing-plans | Tasks, interfaces, checks and review focus from approved spec. Preserves an already chosen execution method; otherwise asks inline versus subagent execution. |
| writing-skills | Baseline/pressure tests for reusable skill instructions. Includes discovery, authoring, flowchart and testing references and rendering helper. Preserve the whole directory. |

## Current integration contracts

The pinned [README](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/README.md)
recommends native marketplace plugins for Claude Code, Codex CLI/App and Cursor.
Historic .codex/INSTALL.md and superpowers-codex bootstrap commands are absent.

- **Claude:** Home Manager `programs.claude-code.plugins.superpowers = source`
  uses native personal plugin loading with Claude >=2.1.157; versions 2.1.76
  through 2.1.156 use HM's compatibility wrapper. Upstream hooks/hooks.json
  injects bootstrap for startup, clear and compact. Do not duplicate individual
  skill copies when using full plugin mode.
- **Codex:** Native `programs.codex.plugins = [ source ]` retains the current
  .codex-plugin manifest and native skills path. Manifest hooks is empty. HM
  generates plugin settings automatically; there must be one config.toml writer.
  Migrating the existing custom merger to HM mutableSettings makes that ownership
  explicit. No historic bootstrap should be synthesized.
- **OpenCode 2:** `programs.opencode.settings.plugins = [ (toString source) ]`
  references the absolute **repository root directory**, containing index.js.
  A configured direct .js file path is rejected. Upstream plugin supports
  >=2.0.4; self-registers skills and injects runtime-specific controller bootstrap
  on context, compaction and generate. Child sessions retain skill access but
  suppress controller bootstrap. Do not separately duplicate its skill set.
- **Cursor:** Upstream ships .cursor-plugin manifest and sessionStart hook.
  The pinned HM Cursor module uses common VS Code support and exposes no
  declarative plugin installer. `.cursor/skills/<native-name>` is a defensible
  skill-only adapter: discovery is supported, but it is not a full plugin with
  startup hook. Do not write Cursor's private marketplace/cache registries.
- **T3:** Inherits selected provider's harness home. There is no upstream T3
  plugin/directory; active T3 orchestration, browser and workspace contracts
  override generic skill tool recipes.

[OpenCode install](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/.opencode/INSTALL.md)
and [implementation](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/.opencode/plugins/superpowers.js)
support local directory loading. Its ESM plugin has no external dependencies;
no runtime npm/Git install is required. Skill scripts need Bash, Git and ordinary
Unix tools. Optional brainstorming visual companion needs Node. Its optional
logo request can be disabled with SUPERPOWERS_DISABLE_TELEMETRY.

## Design implications and limits

Separate immutable collection source, catalog selection and native adapters.
Retain upstream names and complete directories: internal cross-skill links rely
on the sibling layout. Make collection/harness enablement explicit and keep
vendor-owned system skills intact. Skills availability and automatic bootstrap
are distinct behaviors; full framework startup introduces design questions,
review gates and delegation cost. User and repository policy still win.

This was source/configuration inspection; no sessions or account state were
changed and no system was activated. Fresh-session verification is required for
skill discovery and startup hooks in each affected native client after activation.

## Implemented integration

The [Home Manager feature](../../modules/home/dev/agentic-tui/agent-skills.nix)
uses the existing namespaced Matt package through native skill options on all
clients, preserving per-skill selection and the repository's installed names.
The default selects 12 complementary Matt skills, including interview
dependencies; Superpowers is disabled until explicitly enabled.
It uses native Superpowers plugins for Codex and Claude, the root directory
plugin for OpenCode, and skill directories for Cursor. Matt's native plugin
is an upstream alternative, not simultaneously installed by this feature.

Codex settings now use Home Manager's mutable merger, including generated
plugin settings and the existing desktop settings interface. This replaces
the custom activation writer. Home Manager was updated to the upstream
2026-11-15 revision a1293da7dd8e497e08d26173f97e2976b36a31ea.

See the [harness guide](../agents/harnesses.md) for options and update procedure.

Copilot is also selected by the workstation VS Code AI feature. The adapter
installs complete directories under `.copilot/skills`, the current documented
personal location, without using the deprecated `chat.agentSkillsLocations`
setting. See [VS Code skill locations](https://code.visualstudio.com/docs/agent-customization/agent-skills#_skill-locations).
As with Cursor, this is skill discovery rather than plugin startup-hook loading.

## Integration validation

On x86_64-linux, both the desktop Linux and ARM Darwin Home Manager activation
packages evaluated to derivations with the selected clients enabled. This was
cross-platform configuration evaluation, not native Darwin execution. The
pinned Superpowers source, Matt package and Codex skill adapter built, and the
generated Codex marketplace identifies Superpowers 7.0.2. The fetched source
contains all 15 Superpowers skills, its OpenCode entrypoint and Claude hooks.

Focused Nix formatting, dead-code and static analysis, Markdown lint, whitespace
and secret scans passed. The full `just check` run passed documentation checks
but failed Python quality and the dependent formatting/pre-commit checks on
assertions in an existing Azure CLI compatibility script. A Markdown index
spacing issue reported during that run was corrected and focused lint rerun.
No library functions changed. No system closure was built or activated, and
fresh-session discovery, Cursor precedence and native Darwin behavior remain
unverified.

The native Codex merger preserves undeclared settings and follows Home Manager's
serialization behavior. The retired custom merger's special removal of stale
font-face metadata is no longer applied; inspect existing desktop font choices
when validating the first activation.

## Default selection and compatibility review

The default selects 12 Matt skills, covering ordinary engineering tasks while
leaving global workflow controllers optional:

| Purpose | Selected skills | Compatibility reasoning |
| --- | --- | --- |
| Design and terminology | `codebase-design`, `domain-modeling` | Interface design and domain language serve distinct needs; domain modeling also supports the documented interview. |
| Diagnosis and implementation quality | `diagnosing-bugs`, `tdd` | Diagnosis establishes the cause of existing failures; TDD works through agreed new behavior. Repository test policy overrides suggested test types. |
| Review and delivery | `code-review`, `pr` | Code assessment and PR explanation are distinct stages. Review retains its two-axis delegation process, subject to native tool and authorization rules. |
| Investigation | `research` | Provides source-backed investigation and a background researcher when this workflow is invoked; it does not control ordinary implementation. |
| Interviews | `grill-me`, `grill-with-docs`, `grilling` | The two explicitly invoked wrappers serve stateless and persistent-document cases. The shared primitive and domain dependency are included. |
| Continuity and instructions | `handoff`, `writing-for-agents` | Session transfer and reusable instruction design have separate triggers; handoff is explicitly invoked upstream. |

The main duplication comes from process ownership rather than the catalog size.
Superpowers' `using-superpowers` router and Claude/OpenCode hooks can initiate
brainstorming, planning, TDD and delegated review. Matt's `ask-matt`, `implement`
and `implement-spec` provide competing process ownership. Both catalogs also
cover debugging, TDD and review. Full Superpowers therefore stays an explicit
alternative, rather than being stacked on the default Matt workflows.

Setup is a one-time task. Tracker automation needs project conventions and an
explicit workflow. Prototype, teaching, questionnaire and retrospective skills
are useful for particular tasks, but add less to a general engineering default.
These remain selectable, as do all other stable Matt candidates. Interview
selection rejects missing primitive/domain dependencies at evaluation time.

Research and review delegation, debugging reproduction loops and TDD checks are
intentional tradeoffs for tasks that call for those skills. They do not grant
permissions, override repository testing limits or require ceremony for routine
edits. This is source-based compatibility analysis, not a measured productivity
claim. Prefer disabling Matt when opting into full Superpowers, then add only
concrete complementary exceptions. Research coverage does not imply default
enablement of every inspected skill.

The curated configuration was reevaluated on x86_64-linux for both workstation
profiles. Each activation package evaluated successfully, with the same 12 Matt
skills in Codex, Claude and OpenCode and 12 paths each for Cursor and Copilot.
Superpowers was disabled, with no registered plugin in these three native
harnesses and its managed Codex enable flag explicitly false. Focused Nix,
Markdown, whitespace and secret checks passed. This confirms configuration
selection, not live-session discovery; no activation was performed.
