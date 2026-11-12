# Skills and harness integration

The shared catalog in
[`agent-skills.nix`](../../modules/home/dev/agentic-tui/agent-skills.nix)
selects the same portable engineering skills for Codex, Claude Code and OpenCode.
Each client keeps its native installation path, permissions and tool controls.
Complete skill directories preserve supporting references, scripts and invocation
metadata. Package revisions remain owned by the package repository.
The Codex Unslop adapter also supplies `allow_implicit_invocation: false`;
Claude's `disable-model-invocation` field alone is not Codex's native policy.

## Capability bundles

All three clients default to `core`. Add specialists for the projects that need
them rather than loading another complete engineering methodology.

| Bundle | Contents |
| --- | --- |
| `core` | The selected 15 Matt Pocock skills and pstack Unslop |
| `frontend` | Anthropic frontend design |
| `github` | OpenAI address-comments and fix-CI workflows |
| `browser` | OpenAI Playwright and screenshot workflows |
| `documents` | OpenAI PDF workflow |
| `security` | OpenAI security practices, ownership map and threat model |
| `authoring` | Anthropic MCP builder and skill creator |

Codex uses its native PDF, browser and skill-creator capabilities instead of
installing those duplicate workflows from a bundle. Selecting a bundle does not
install or connect a Codex plugin. Confirm the native capability in the active
surface before using it. Bundles install instructions; required runtimes, tools
and account connections remain separate prerequisites.

Configure a client's complete selection in a Home Manager module:

```nix
programs.agent-skills.clients.claude.bundles = [
  "core"
  "frontend"
  "github"
];
programs.agent-skills.clients.opencode.extraSkills.project-domain =
  ./skills/project-domain;
```

Client names are `codex`, `claude`, and `opencode`. An empty bundle list removes
catalog skills from that client, while preserving its directly configured and
unmanaged skills. OpenCode also discovers Claude's skill directory. The module
therefore denies omitted catalog IDs through OpenCode's skill permissions,
including IDs installed only for Claude. This affects catalog IDs, not arbitrary
unmanaged skills. Explicit client permission overrides remain possible through
Home Manager. Extensions must use different names from selected catalog
skills. Prefer a complete directory to a single Markdown file so references and
metadata survive installation. Existing Apple Reminders, REA and OpenCode Typst
integration remain owned by their feature modules.

The default OpenCode catalog is intentionally smaller than its earlier selection.
Use bundles to restore needed specialists. Deployment and broad suite routers
are not default skills. Vercel's React/composition skills and Trail of Bits'
security workflows are useful project-specific candidates; package and review
their dependency/tool requirements before adding them through `extraSkills`.

## Workflow and tool ownership

The [shared client guidance](../../modules/home/dev/agentic-tui/agent-skills-guidance.md)
defines routing and evidence rules. Repository instructions remain authoritative
for checkout placement, validation, authorization and cleanup. The separately
installed `engineering-workflow` skill is optional and user-managed; this module
does not replace it or promise its availability in every client. Follow
[coordination guidance](coordination.md) for durable task briefs and handoffs.

In T3, use its orchestration and shared browser under the active session's rules.
Use native subagents only where those rules allow them. In a standalone client,
use the available native tools and the repository's checkout/lifetime commands.
Do not install an MCP server solely to reproduce an existing shell, filesystem,
Git, browser, or search tool. Use the existing GitHub connector or CLI first.

Keep REA disabled until needed. Browser helpers, persistent kernels and temporary
MCP transports belong to their tasks and need explicit teardown. A deferred tool
catalog, a cached plugin, a connected account and a running transport are
different states. Removing cached plugins does not prove a startup improvement.

REA uses its Nix-pinned runtime and complete matching skill bundle in all three
clients. Its injected [lifecycle guidance](../../modules/home/dev/agentic-tui/rea-lifecycle.md)
keeps live sessions while an active task or requested follow-up needs them,
including pauses. Ordinary browser work follows the active harness's browser
route; specialized REA captures also require that route to be permitted.
Use the installed CLI rather than mutable npm setup or self-update. External
analysis engines are selected per target; the package deliberately omits the
optional Frida provider. See the
[package contract](../../pkgs/pkgs/by-name/re/rea/README.md) and
[upstream installation guidance](https://github.com/morluto/rea/blob/160d821ac9a0310afcb8d1fc427862dd6508add5/docs/installation.md).
As checked on 2026-11-08, the pinned 6.8.0 is the current stable release.

`checks.<system>.rea` checks the real client-generated skill directories,
preserves the release's reference bundle, verifies Codex's disabled startup
defaults and unrelated MCP integration, and reruns the package's isolated
CLI/MCP/PTY checks. Disabled clients receive no REA skill. Darwin's sandbox
still requires the package's documented outside-sandbox static-analysis check;
optional engines and native browser/UI behavior need their own acceptance.

Context7 or MCP-NixOS can be trialed for recurring documentation/discovery gaps.
Pinned source, evaluation, builds and runtime observations remain the authority
for this repository. Configure a missing server using the client's supported
native MCP integration and credentials outside the Nix store. Codex's writable
configuration is owned by `programs.chatgpt.settings`; do not introduce a second
writer through `programs.codex.settings` or general MCP integration.

Application-owned productivity and artifact connections are preserved. Skill
bundles are declarative capability selections, not isolated credentials or runtime
plugin profiles. Do not imply that selecting `core` disconnects application
plugins. Keep broad Work capabilities available in the surfaces that need them,
and select only the relevant tools during coding.

## Alternative methodology trials

Superpowers and pstack's full workflow are alternatives to the default process.
Use a separate explicit trial and the publisher's adapter for the installed
harness version. Do not bootstrap multiple suite routers in the same session.
Preserve existing task authorization, model choices, T3-owned isolation and
immutable validation receipts. Never let a generic suite clean up application
worktrees or repeat a queued operation whose status is unknown.

As reviewed on 2026-11-08, Superpowers 7.0.2 declares native Codex and OpenCode
support, and pstack 0.15.36 provides a first-party Claude Code adapter. These
support claims do not establish compatibility with this repository's workflow.
See the [Superpowers adapter](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/docs/README.opencode.md)
and [pstack adapter](https://github.com/cursor/plugins/blob/6b0300214a09fd6029cfb7077043125758cd1fd2/pstack/docs/harness/claude-code.md).

## Qualification

OpenCode uses native V2 `plugins`, ordered `permissions`, and `update` settings.
Its authentication and notification plugins are pinned to V2-capable releases;
the plugin SDK is not itself installed as a runtime extension. Nix pins the
top-level plugin versions. OpenCode resolves their dependency graph in its own
cache, so this is not a Nix-vendored transitive dependency closure. The generated
configuration is checked against the schema shipped with the selected package.
Schema acceptance does not establish provider authentication or native alerts.

V2 intentionally preserves `lsp` syntax without running language servers or
exposing their diagnostics. The inactive LSP setup and obsolete experimental
environment flags have been removed. Use the project's declared lint, typecheck
and compiler checks, as the installed client guidance specifies. See the
[upstream migration contract](https://opencode.ai/docs/migrate-v1/).

The pinned Home Manager MCP adapter still emits supported compatibility forms.
Use native `settings.mcp.servers` for client-specific V2 declarations; preserve
the standard adapter for existing shared registrations until upstream changes
its contract. Do not infer complete behavior merely from a schema field.

The [T3 service guide](../operations/t3-code.md) covers native Home Manager
integration, provider binary/home selection, state ownership and activation.
Codex's existing device-managed REA startup default intentionally keeps the
supported `managed_config.toml` mechanism: ordinary system defaults have lower
precedence and would not retire a saved enabled registration at startup. This
limited compatibility use is distinct from an enforced permission requirement.
See [OpenAI's managed configuration guidance](https://learn.chatgpt.com/docs/enterprise/managed-configuration).

`checks.<system>.agent-skills` evaluates the real Home Manager consumers and
checks their generated skill links against packaged supporting files and
explicit-only metadata. It exercises default parity, bundle isolation, custom
extensions, invalid names, collisions, and disabled clients. It does not invoke
a model, authenticate services, or establish the quality of a workflow.

After home activation, restart each client and verify its actual skill inventory
and CODEX_HOME. Preserve existing skills on any collision; inspect whether they
are managed or user-owned before reconciling them. Run trial prompts in a
disposable project with the same model/settings and source inputs:

| Case | Expected observation |
| --- | --- |
| Explain one configuration value | Direct answer; no interview, delegation or edits |
| Make a small authorized change | Focused implementation and relevant checks |
| Diagnose a reproducible bug | A command that catches the exact symptom before a fix claim |
| Implement behavior test-first | Public-interface test boundaries honor existing agreement |
| Review staged, unstaged and new files | All three inputs included; standards/spec findings separated |
| Research an API | Primary citations and explicit unverified limits |
| Inspect an app in T3's browser | T3's browser route and task-owned cleanup |
| Resume a queued check | Reconcile its existing ID and frozen source before another submission |
| Edit prose with Unslop | Facts, identifiers and quotations preserved |

Record completion quality, missed requirements, unnecessary questions, wrong
skill/tool selection, repeated work, actual check results, and resource cleanup.
Include non-trigger cases. Omitted acceptance checks fail the trial even if it
finishes quickly. Do not claim a productivity improvement from installation or
one successful prompt. Claude authentication and native macOS runtime behavior
need their own checks on those surfaces.
