{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  hyprlandPackages = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  programs.hyprland = {
    enable = true;

    # Keep the compositor and portal on one upstream revision. Both link
    # against the Hyprland flake's shared library inputs.
    package = hyprlandPackages.hyprland;
    portalPackage = hyprlandPackages.xdg-desktop-portal-hyprland;

    # Keep XWayland available for the remaining applications and games that
    # have not migrated to native Wayland. Native Wayland clients remain the
    # preferred path through the session environment, but compatibility should
    # not require per-host compositor overrides.
    xwayland.enable = true;

    # UWSM owns the systemd user-session lifecycle: it imports the Wayland
    # activation environment, reaches graphical-session.target at the right
    # time, starts XDG autostart entries, and tears the session down cleanly.
    withUWSM = true;

    # Modern Hyprland leaves this opt-in, but systemd user services still need
    # the active NixOS system profile in PATH for reliable desktop-entry and
    # xdg-open launches.
    systemd.setPath.enable = true;
  };

  # ScreenCast and RemoteDesktop portals transport frames over PipeWire. Use
  # composable defaults so a specialised host can deliberately replace the
  # media-session policy, while ordinary Hyprland hosts work out of the box.
  services.pipewire = {
    enable = lib.mkDefault true;
    wireplumber.enable = lib.mkDefault true;
  };

  xdg.portal = {
    # The upstream NixOS Hyprland module owns the matching portal package,
    # its D-Bus activation metadata, and the Hyprland-supplied portals.conf.
    # Only select the backend order here.  A Hyprland session needs its own
    # backend for capture and remote-desktop interfaces; GTK is the portable
    # fallback for interfaces Hyprland does not implement.
    xdgOpenUsePortal = true;
    config.hyprland.default = [
      "hyprland"
      "gtk"
    ];
  };

  security.pam.services.hyprlock = { };

  assertions = [
    {
      assertion = config.programs.uwsm.enable;
      message = "Hyprland baseline requires UWSM when programs.hyprland.withUWSM is enabled.";
    }
    {
      assertion = config.services.dbus.enable;
      message = "Hyprland baseline requires D-Bus for the session and XDG Desktop Portals.";
    }
    {
      assertion = config.xdg.portal.enable;
      message = "Hyprland baseline requires xdg.portal for file access, screencasting, and remote-desktop mediation.";
    }
    {
      assertion = config.services.pipewire.enable && config.services.pipewire.wireplumber.enable;
      message = "Hyprland screencasting requires PipeWire and WirePlumber.";
    }
  ];
}
