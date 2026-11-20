# Harness integration

Nix installs shared skills through the selectable
[`dev-agentic-tui-agent-skills`](../../modules/home/dev/agentic-tui/agent-skills.nix)
Home Manager feature, included by the workstation `dev` selection. It exposes
12 complementary Matt Pocock skills for design, interviews, debugging, research,
TDD, review, PR writing, handoff and agent documentation. Superpowers 7.0.2 is available as an explicit opt-in.
Vendor skills remain owned
by their applications. Repository instructions and the active harness control
tool routing, permissions and workflow scope.

`programs.agent-skills` separates catalog selection from harness adapters:

- `enable` disables the complete feature.
- `mattpocock.enable` controls the curated default catalog.
- `superpowers.enable` opts into the complete Superpowers workflow and hooks.
- `mattpocock.skills` replaces the default selection with chosen stable names.
- `clients.<name>.enable` controls Codex, Claude Code, OpenCode, Cursor or Copilot.
- `extraSkills` adds complete local skill directories under unique names.

The default selection covers common engineering tasks without installing a
global execution controller. Interview wrappers include `grilling` and
`domain-modeling`, so their dependencies are available. Research and review
retain their upstream delegation behavior when invoked; repository permissions
and the active harness still control how that work runs. TDD and debugging
retain their focused verification processes, with repository test policy taking
precedence. This is a compatibility judgment from source review, not a measured
productivity claim.

The [workflow guide](workflows.md) names the default skills. The remaining
stable catalog stays selectable through `mattpocock.skills`, which replaces
the default list. Add tracker, prototype, teaching or other specialist workflows
when their prerequisites and purpose apply.

Superpowers brings an integrated planning/execution process; enabling it also
loads its whole skill catalog. Its Claude/OpenCode startup guidance can route
ordinary tasks through that process. For that alternative, prefer one workflow
owner:

```nix
programs.agent-skills = {
  mattpocock.enable = false;
  superpowers.enable = true;
};
```

Keep any mixed selection deliberate: Matt and Superpowers both cover diagnosis,
TDD, planning and review, and their controllers can trigger different gates for
the same task. Avoid adding both sets of controllers to the default catalog.

Matt skills use Home Manager's native `programs.<client>.skills` options, with
`mattpocock-` names matching the packaged frontmatter. This deliberately uses
immutable skill directories rather than the auto-updating upstream plugin;
do not install a second Matt plugin alongside them. Supporting files remain
available. Resolve upstream references such as `/tdd` to `mattpocock-tdd` and
load the referenced skill using the active harness's available tools.

When explicitly enabled, Superpowers uses native Home Manager Codex and Claude plugins. OpenCode uses
the upstream v2 directory plugin, which registers its own skills and bootstrap.
Cursor and Copilot receive complete skill directories under `.cursor/skills` and `.copilot/skills`, without
plugin startup hooks. Cursor also discovers compatible Claude/Codex directories;
check precedence and duplicates in a fresh session after activation. T3 inherits
the configured provider's native integration; it needs no separate skill tree.

The [catalog research](../research/agent-skills-catalogs-research.md) inventories
all 54 upstream skills, including the 12 Matt skills excluded by the stable
plugin manifest, and records compatibility limits. Installation does not run
setup skills or authorize external writes. Superpowers startup guidance is
active in its Claude and OpenCode plugins; repository test, review and
orchestration rules take precedence over upstream workflow examples.

Update the Matt package source through its owning package repository. Update
the Superpowers version, revision and hash together in the feature, reviewing its
manifests, hooks, skill inventory and OpenCode minimum version. Reevaluate both
home profiles, activate through the normal host workflow, then reload each
client and inspect skills in a fresh session.

Codex plugin preferences are declared in
[`plugins.nix`](../../modules/home/dev/agentic-gui/codex/plugins.nix).
The shared policy applies to both workstation profiles. It disables the retired
artifact, publishing and pet plugins, blocks the selected connected apps, and
leaves Codex Security disabled in ordinary sessions. Select the explicit
Security profile with `codex --profile security` when needed.

Computer Use is disabled on Linux. The Codex launcher disables the desktop-only
App Tools plugin for T3-origin sessions. REA uses native MCP configuration in
Codex, Claude Code and OpenCode; no REA skill or custom launcher is installed.

Codex's writable configuration is merged by Home Manager's native
`programs.codex.mutableSettings`. `programs.chatgpt.settings` remains the desktop
policy interface and feeds `programs.codex.settings`; plugin-generated settings
join the same merger. Do not introduce a second activation writer. Account-default
plugins may remain installed remotely even when the local policy disables them.
Deleting cached plugin files alone does not disable an account-default plugin.

## REA on demand

The [REA module](../../modules/home/dev/agentic-tui/rea.nix) registers the packaged
`rea mcp` command with the existing harnesses. Use ordinary Codex, Claude Code,
OpenCode and T3 sessions and ask for REA when an investigation needs it. No
special executable, harness, profile, skill, or manual server toggle is required.
Existing skill-loading policy is unchanged.

On-demand loading here means native tool discovery. The client may start REA to
read its catalog and retain an idle server process. This does not provide
zero-process idle operation. Compact input schemas are explicitly selected for
all clients, preserving the full tool set and server-side validation.

| Harness | Native integration |
| --- | --- |
| Codex CLI and desktop | Enabled `mcp_servers.rea` in the existing writable configuration; Codex owns incremental tool discovery |
| Claude Code | Home Manager's native MCP registration, `alwaysLoad = false` for REA, and `ENABLE_TOOL_SEARCH = true` in native settings |
| OpenCode 2 | Enabled `mcp.servers.rea` with `codemode = true`, exposing tools through native Code Mode discovery |
| T3 Code | Existing provider instances inherit their respective native harness configuration; no new instances or binaries |

Claude Code's tool search setting affects MCP tool discovery, not skill loading.
With the configured Claude Code version, Home Manager writes personal-plugin
configuration and keeps the selected Claude executable unchanged. Tool search
requires a supported model and compatible gateway; a client fallback can change
context costs. The installed Codex release owns its incremental/deferred tool
behavior; do not add removed `tool_search` feature flags.

Reload clients after activation and inspect a fresh session. Use `/mcp` in
Codex or Claude, or `/mcps` in OpenCode, to inspect the connection. Native menus
also allow manually disconnecting the server if desired. An older system
generation may still supply `/etc/codex/managed_config.toml` forcing REA off;
that machine-level policy requires a system activation to retire, since a Home
Manager activation cannot remove a system-owned file.

REA supplies six native MCP prompts, including `investigate_feature` and
`trace_crash`, as optional workflow guidance. Direct tool calls remain available;
evidence comes inline and does not require fetching MCP resources. For CLI
discovery use `rea <command> --help`, `rea --llms`, or `rea capabilities --json`.
Do not run `rea setup` over the declarative configuration: setup also installs
instructions and writes client configuration. Optional analysis engines remain
separately supplied. See the [package contract](../../pkgs/pkgs/by-name/re/rea/README.md)
and [integration research](../research/rea-harness-integration-research.md).

The [T3 service guide](../operations/t3-code.md) covers provider binary and home
selection, state ownership and activation. Follow the active harness's tool and
browser routing and the repository's [coordination guidance](coordination.md).
After changing configuration, reload the affected client and inspect a fresh
session; edits cannot erase context already supplied to a running session.
