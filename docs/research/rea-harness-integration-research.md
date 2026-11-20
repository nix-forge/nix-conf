# Native REA registration and on-demand tool discovery

Reviewed: 2026-11-16. Scope: REA 6.8.0
(`160d821ac9a0310afcb8d1fc427862dd6508add5`), Codex CLI 0.167.0,
Claude Code 2.1.303, OpenCode 2.0.32, and Home Manager
`b787c48e2ec57a9d098f5c2721882a3bc1e16f97`.

## Answer

Register REA in each existing harness and use native tool discovery. An idle
server process is acceptable; the goal is to avoid advertising every REA tool's
full schema upfront. No custom executable, harness, profile or skill is needed.
Existing skill-loading policy is independent and remains unchanged.

## Findings and sources

- [REA's pinned README](https://github.com/morluto/rea/blob/160d821ac9a0310afcb8d1fc427862dd6508add5/README.md)
  documents compact input schemas, retaining all tools and full server-side
  validation. Set `REA_MCP_INPUT_SCHEMA_PROFILE=compact` on the server to avoid
  inheriting a full-schema override. Compact schemas reduce per-tool overhead;
  discovery controls when tools enter model context.
- [REA's native prompts](https://github.com/morluto/rea/blob/160d821ac9a0310afcb8d1fc427862dd6508add5/docs/mcp-prompts.md)
  supply six optional investigation workflows. Evidence is returned inline and
  does not require an MCP resource fetch. No generated or modified skill is
  necessary for tool access.
- [Codex's native MCP configuration](https://developers.openai.com/codex/mcp/)
  shares enabled server registrations between local CLI and desktop clients.
  Installed `codex features list` reports `incremental_tools` and
  `deferred_tool_world_state` stable and enabled; the older `tool_search` and
  `tool_search_always_defer_mcp_tools` flags are removed. Keep discovery owned by
  this runtime rather than adding obsolete flags or a proxy. Feature status is
  an observation, not a measurement of the tool payload on every model request.
- [Claude's tool search documentation](https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search)
  supports `ENABLE_TOOL_SEARCH=true` in native settings to enable deferral
  without waiting for the automatic context-size threshold. The server-specific
  `alwaysLoad=false` keeps REA tools deferred, including tools that request
  upfront loading. These settings concern tools, not skills. Compatible models
  and gateways are required; upstream documents exceptions and fallbacks.
- The pinned [Home Manager Claude module](https://github.com/nix-community/home-manager/blob/b787c48e2ec57a9d098f5c2721882a3bc1e16f97/modules/programs/claude-code/default.nix)
  installs declared MCP configuration as a native personal plugin on Claude Code
  2.1.157 and later. It retains the selected executable. The synthesized plugin
  contains MCP JSON and its manifest; it needs no custom skill or program.
- [OpenCode's v2 MCP configuration](https://opencode.ai/docs/mcp-servers)
  uses `mcp.servers.<name>`, `disabled=false`, and native Code Mode by default.
  Explicit `codemode=true` keeps REA behind Code Mode discovery instead of placing
  every tool on the provider's native tool list. A connected server can persist
  in OpenCode's shared background service.

## Implication for this repository

The [REA module](../../modules/home/dev/agentic-tui/rea.nix) installs only the
existing REA package and declares native integrations. Codex uses the existing
writable settings owner; Claude uses `programs.claude-code.mcpServers` and native
tool-search settings; OpenCode uses its v2 configuration. No REA launcher, custom
profile, instruction injection, proxy or additional service is installed.

T3 continues using its existing provider binaries and native configuration.
The [harness guide](../agents/harnesses.md#rea-on-demand) records usage and
activation prerequisites. Optional engines remain separately supplied under the
[package contract](../../pkgs/pkgs/by-name/re/rea/README.md). Do not run upstream
setup over these declarations: setup also installs instructions and writes
mutable configuration.

## Validation and limits

On x86_64-linux, focused evaluation of both the desktop and Darwin home settings
passed. Both select enabled REA registrations and native discovery configuration;
Claude's `finalPackage` equals its configured `package`, confirming no wrapper is
introduced by this integration. Nixfmt, Deadnix, Statix and the staged Gitleaks
check passed. Existing skill settings were not modified.

The installed REA 6.8.0 previously completed MCP initialization, enumerated 229
tools and six prompts, rendered `investigate_feature`, and exited with status
zero after stdin closed. That protocol check remains applicable: this revision
changes client registration and discovery settings, not the REA executable.

`just check` was attempted and stopped on an unrelated untracked
`overlays/temporary/swift-clang-hardening.nix` referenced by the concurrently
modified configuration. A broader package-list evaluation separately encountered
an untracked `overlays/temporary/azure-cli-invoke.nix`. Those files were not staged
or changed for this task. Full flake validation therefore has not passed.

The running system still supplies a legacy `/etc/codex/managed_config.toml`
forcing REA disabled. A resolved app-server configuration check showed that this
machine-level layer overrides user settings. The checkout no longer declares it;
a system activation must retire that policy before native Codex discovery can
use REA. No full desktop build or activation was performed.

No authenticated model request, graphical client session, native macOS run,
T3 end-to-end run, optional engine analysis, or per-request context-size
measurement was performed. Native discovery depends on the chosen model and
client; an idle server and small discovery metadata remain expected overhead.
