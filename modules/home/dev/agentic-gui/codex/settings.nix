{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  cfg = config.programs.chatgpt;
  updater = pkgs.writers.writePython3Bin "configure-codex-desktop-settings" {
    libraries = [ pkgs.python3Packages.tomlkit ];
    flakeIgnore = [ "E501" ];
  } ./configure_codex_desktop_settings.py;
  managedSettings = pkgs.writeText "codex-desktop-settings.json" (builtins.toJSON cfg.settings);
  configure = (myLib.writers.writeBashTemplate { inherit pkgs; }) {
    name = "configure-codex-desktop-settings";
    src = ./configure-codex-desktop-settings.sh.in;
    replacements = {
      shell = lib.getExe pkgs.bash;
      inherit managedSettings;
      updater = lib.getExe updater;
      codexConfig = lib.escapeShellArg "${cfg.codexHome}/config.toml";
    };
  };
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
        Declarative native Codex desktop settings. Home Manager merges these
        fields into the writable Codex configuration on activation, preserving
        app-owned trust, session preferences, and unconfigured settings.
      '';
    };
    settingsPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = configure;
      description = "Command that applies the merged declarative desktop settings.";
    };
  };

  config = {
    assertions = [
      {
        assertion =
          !config.programs.codex.enable
          || builtins.elem config.programs.codex.settings [
            null
            { }
          ];
        message = "Shared writable Codex configuration is owned by programs.chatgpt.settings; move nonempty programs.codex.settings there to avoid competing config.toml writers.";
      }
    ];
    # Core inheritance omits CODEX_HOME. This shared owner covers GUI-only
    # profiles too, without broadening inheritance or credential exclusions.
    programs.chatgpt.settings.shell_environment_policy.set.CODEX_HOME = cfg.codexHome;
    home.activation.configureCodexDesktopSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe pkgs.bash} ${configure}
    '';
  };
}
