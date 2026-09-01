{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.system;
in
{
  options.desktop.system.enable = lib.mkEnableOption "services needed by an interactive standalone Wayland desktop";

  config = lib.mkIf cfg.enable {
    # GTK and libadwaita store several user-facing settings through dconf.
    # Keep the service system-wide while individual applications remain in
    # Home Manager, where they can be selected independently.
    programs.dconf.enable = true;

    # Upower and power-profiles-daemon provide the D-Bus APIs used by Waybar
    # and ordinary desktop control panels. Do not enable TLP alongside this
    # module: it would compete for the same power policy.
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;

    # Mount authorization remains with UDisks and Polkit. The GTK4 file
    # manager itself is configured per-user by the Home Manager desktop module.

    environment.systemPackages = [
      pkgs.ddcutil
      pkgs.wev
    ];
  };
}
