{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  options.desktop.enable = lib.mkEnableOption "a complete, Wayland-native interactive desktop layer";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "The interactive desktop layer is supported on Linux only.";
      }
    ];

    # This is intentionally a composition point, not a monolith. A smaller
    # profile can select `desktop-bar`, `desktop-capture`, or another child
    # module directly and enable only that capability.
    desktop = {
      launcher.enable = lib.mkDefault true;
      bar.enable = lib.mkDefault true;
      notifications.enable = lib.mkDefault true;
      osd.enable = lib.mkDefault true;
      idle.enable = lib.mkDefault true;
      clipboard.enable = lib.mkDefault true;
      capture.enable = lib.mkDefault true;
      applications.enable = lib.mkDefault true;
      workflow.enable = lib.mkDefault true;
      wallpaper.enable = lib.mkDefault true;
    };
  };
}
