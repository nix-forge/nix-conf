{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
  cfg = config.programs.bitwardenDesktop;
  render = import ../../lib/templates/text.nix;
  darwinAppPath = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/Bitwarden.app";
  waitForApp = render ./bitwarden-assets/wait-for-app.sh.in {
    app = lib.escapeShellArg darwinAppPath;
  };
  startApp = pkgs.writeShellScript "bitwarden-start" (
    render ./bitwarden-assets/start-app.sh.in { app = lib.escapeShellArg darwinAppPath; }
  );

in
{
  imports = [ ./macos/application-capabilities.nix ];
  options.programs.bitwardenDesktop = {
    package = lib.mkOption {
      type = lib.types.package;
      internal = true;
      default =
        if isDarwin && pkgs ? bitwarden-desktop-bin then
          pkgs.bitwarden-desktop-bin
        else
          pkgs.bitwarden-desktop;
      description = "Bitwarden desktop package used by the app and browser-integration bridge.";
    };

    startAtLogin = lib.mkEnableOption "starting Bitwarden's browser-integration bridge at login";
  };

  config = {

    macos.applicationCapabilities.apps.bitwarden = lib.mkIf isDarwin {
      enable = lib.mkDefault true;
      bundle = "Bitwarden.app";
      bundleId = "com.bitwarden.desktop";
      features.browserIntegration = {
        enable = lib.mkDefault true;
        service = "browser-integration";
        reason = "Unlock the selected browser extension using the desktop biometric bridge";
        source = "https://contributing.bitwarden.com/getting-started/clients/browser/biometric/";
        instruction = "Enable the desktop/native-messaging integration and user biometrics, then unlock the chosen extension using Touch ID. Do not grant Full Disk Access or Accessibility for this feature.";
      };
    };

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
      lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "copyApps" ] waitForApp
    );

    launchd.agents.bitwarden = lib.mkIf (isDarwin && cfg.startAtLogin) {
      enable = true;
      domain = "gui";
      config = {
        ProgramArguments = [ (toString startApp) ];
        RunAtLoad = true;
        KeepAlive = false;
        ProcessType = "Interactive";
      };
    };
  };
}
