let
  runtime = { lib, pkgs, ... }: {
    # Keep REA out of automatic per-chat startup even when a saved user setting
    # re-enables it. The CLI and explicitly owned stdio sessions remain usable.
    # Managed defaults apply at client startup, not as an MCP approval policy.
    environment.etc."codex/managed_config.toml".source =
      (pkgs.formats.toml { }).generate "codex-runtime-defaults.toml"
        {
          mcp_servers.rea = {
            command = lib.getExe pkgs.rea;
            args = [ "mcp" ];
            enabled = false;
          };
        };
  };
in
{
  nixos = runtime;
  darwin = runtime;
}
