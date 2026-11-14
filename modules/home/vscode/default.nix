{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.vscode;
in
{
  key = "nix-conf/vscode/homeManager";
  imports = [
    ../macos/applications.nix
    ./settings.nix
    ./keybinds.nix
  ];

  options.programs.vscode.passwordStore = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = if pkgs.stdenv.hostPlatform.isLinux then "gnome-libsecret" else null;
    description = ''
      Electron password storage backend for the default VS Code package.
      Linux defaults to the Secret Service API because automatic detection
      misses desktops such as Hyprland. Set null to use automatic detection.
      A custom programs.vscode.package must configure its own launcher flags.
    '';
  };

  config.macos.applications.commands.code = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    bundle = "Visual Studio Code.app";
    executable = "Contents/Resources/app/bin/code";
  };

  config.programs.vscode = {
    enable = true;
    # Keep argv.json writable: VS Code updates crash-reporting metadata there.
    # The package's supported launcher option covers CLI and desktop launches.
    package = lib.mkDefault (
      if cfg.passwordStore == null then
        pkgs.vscode
      else
        pkgs.vscode.override (old: {
          commandLineArgs = lib.concatStringsSep " " [
            (old.commandLineArgs or "")
            (lib.escapeShellArg "--password-store=${cfg.passwordStore}")
          ];
        })
    );
    mutableExtensionsDir = false;
    profiles.default = {
      enableExtensionUpdateCheck = false;
      # Home Manager still emits the retired boolean. VS Code 1.142 migrates
      # it on every startup, attempting to edit our immutable settings file.
      userSettings = lib.mkIf (lib.versionAtLeast cfg.extensionCompatibilityVersion "1.142.0") {
        "extensions.autoUpdate" = lib.mkForce "off";
      };
      enableUpdateCheck = false;
    };
  };
}
