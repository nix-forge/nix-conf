{
  config,
  lib,
  pkgs,
  ...
}:
let
  command = lib.getExe pkgs.rea;
  args = [ "mcp" ];
  # Compact schemas retain every tool and server-side validation.
  env.REA_MCP_INPUT_SCHEMA_PROFILE = "compact";
in
{
  imports = [ ../agentic-gui/codex/settings.nix ];

  home.packages = [ pkgs.rea ];

  programs = {
    # Current Claude Code uses native personal-plugin configuration, leaving its
    # executable unchanged. Tool search does not change skill-loading policy.
    claude-code = lib.mkIf config.programs.claude-code.enable {
      mcpServers.rea = {
        inherit command args env;
        alwaysLoad = false;
      };
      settings.env.ENABLE_TOOL_SEARCH = "true";
    };

    # Use the writable-settings owner shared by CLI, desktop and T3. Codex owns
    # native discovery; do not add removed tool_search flags or a second writer.
    chatgpt.settings = lib.mkIf config.programs.codex.enable {
      mcp_servers.rea = {
        inherit command args env;
        enabled = true;
      };
    };

    # OpenCode 2 uses mcp.servers and disabled, unlike the v1 schema. Code Mode
    # discovers tools instead of placing every schema on the native tool list.
    opencode.settings = lib.mkIf config.programs.opencode.enable {
      mcp.servers.rea = {
        type = "local";
        command = [ command ] ++ args;
        environment = env;
        disabled = false;
        codemode = true;
      };
    };
  };
}
