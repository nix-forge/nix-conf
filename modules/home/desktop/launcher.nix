{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.launcher;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  options.desktop.launcher.enable = lib.mkEnableOption "the Fuzzel application launcher";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "desktop.launcher is supported on Linux only.";
      }
    ];

    # Keep this module deliberately light. Hosts can provide a complete
    # Fuzzel theme and Hyprland bindings without forcing those UX decisions on
    # every consumer of the launcher.
    programs.fuzzel.enable = true;
  };
}
