{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./settings.nix ];

  # Preserve the launcher for explicit use, but do not start one server per chat.
  # An explicit disabled entry also retires an older writable registration.
  programs.chatgpt.settings = lib.mkIf config.programs.codex.enable {
    mcp_servers.rea = {
      command = lib.getExe pkgs.rea;
      args = [ "mcp" ];
      enabled = false;
    };
  };
}
