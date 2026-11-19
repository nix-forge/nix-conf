{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.vscode;
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.vscode.remote.enable =
    lib.mkEnableOption ''
      the declarative Remote SSH extension host, using this machine's default
      profile extensions and settings
    ''
    // {
      default = true;
    };

  config = lib.mkIf (cfg.enable && cfg.remote.enable) {
    assertions = [
      {
        assertion = !cfg.mutableExtensionsDir;
        message = "VS Code's declarative Remote SSH host requires mutableExtensionsDir = false.";
      }
      {
        assertion = builtins.isAttrs cfg.profiles.default.userSettings;
        message = "VS Code's declarative Remote SSH host requires attribute-set userSettings.";
      }
    ];

    home.file = {
      # Reuse Home Manager's extension tree and extensions.json, including its
      # Nix-patched native dependencies and platform-specific catalog packages.
      # Remote SSH chooses UI/workspace placement from extension manifests.
      # Never copy extensions from the connecting client (which may use a
      # different architecture), or install unpinned Marketplace defaults.
      ".vscode-server/extensions".source = config.home.file.".vscode/extensions".source;

      # Remote machine settings take precedence over the connecting client's
      # user settings. Generate them on the destination so language servers,
      # formatters, direnv and terminal shells use its own Nix store paths.
      # VS Code applies only settings whose scopes permit remote overrides.
      ".vscode-server/data/Machine/settings.json".source =
        jsonFormat.generate "vscode-remote-settings.json" cfg.profiles.default.userSettings;
    };
  };
}
