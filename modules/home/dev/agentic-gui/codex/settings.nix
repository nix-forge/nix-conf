{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.chatgpt;

in
{
  options.programs.chatgpt = {
    codexHome = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default =
        if config.home.preferXdgDirectories then
          "${config.xdg.configHome}/codex"
        else
          "${config.home.homeDirectory}/.codex";
      description = "Codex state directory matching Home Manager's directory preference, shared by the CLI default and writable settings merger.";
    };
    settings = lib.mkOption {
      inherit ((pkgs.formats.toml { })) type;
      default = { };
      description = ''
        Declarative native Codex desktop settings. Home Manager's native Codex module merges these
        fields into the writable Codex configuration on activation, preserving
        app-owned trust, session preferences, and unconfigured settings.
      '';
    };

  };

  config = {
    # Home Manager owns both plugin-generated and declared native settings.
    # Keep chatgpt.settings as the desktop policy interface, with one writable
    # merger so CLI, desktop and T3 cannot race competing activation writers.
    programs.codex = {
      mutableSettings = true;
      inherit (cfg) settings;
    };
    programs.chatgpt.settings.shell_environment_policy.set.CODEX_HOME = cfg.codexHome;
    programs.chatgpt.settings.desktop.git-worktree-root = lib.mkIf (config.programs.dev-worktree.enable
      or false
    ) (lib.mkDefault "${config.programs.dev-worktree.worktreeRoot}/codex");
  };
}
