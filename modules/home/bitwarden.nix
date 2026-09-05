{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
  cfg = config.programs.bitwardenDesktop;
  darwinAppPath = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/Bitwarden.app";
in
{
  options.programs.bitwardenDesktop = {
    package = lib.mkOption {
      type = lib.types.package;
      internal = true;
      default = pkgs.bitwarden-desktop;
      description = "Bitwarden desktop package used by the app and browser-integration bridge.";
    };

    startAtLogin = lib.mkEnableOption "starting Bitwarden's browser-integration bridge at login";
  };

  config = {
    home.packages = [
      pkgs.bitwarden-cli
      cfg.package
    ];

    # Browser biometric unlock needs the desktop native-messaging bridge to be
    # alive. The --autostart path honors Bitwarden's own "Start to tray" setting
    # without granting the application any additional privilege.
    xdg.configFile."autostart/bitwarden.desktop" = lib.mkIf (isLinux && cfg.startAtLogin) {
      text = ''
        [Desktop Entry]
        Type=Application
        Name=Bitwarden
        Comment=Start the Bitwarden browser integration bridge
        Exec=${lib.getExe cfg.package} --autostart
        Terminal=false
        X-GNOME-Autostart-enabled=true
      '';
    };

    # A stable, real application copy preserves LaunchServices, Keychain, and
    # native-messaging behavior. It also prevents a launch agent from pointing
    # at a generation-specific Nix store path.
    targets.darwin.copyApps.enable = lib.mkIf isDarwin (lib.mkDefault true);

    home.activation.waitForCopiedBitwardenApp = lib.mkIf (isDarwin && cfg.startAtLogin) (
      lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "copyApps" ] ''
        run /bin/wait4path ${lib.escapeShellArg darwinAppPath}
      ''
    );

    launchd.agents.bitwarden = lib.mkIf (isDarwin && cfg.startAtLogin) {
      enable = true;
      domain = "gui";
      config = {
        ProgramArguments = [
          "/bin/sh"
          "-c"
          "/bin/wait4path ${lib.escapeShellArg darwinAppPath} && exec /usr/bin/open -gj -a ${lib.escapeShellArg darwinAppPath}"
        ];
        RunAtLoad = true;
        KeepAlive = false;
        ProcessType = "Interactive";
      };
    };
  };
}
