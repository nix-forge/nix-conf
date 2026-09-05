{ lib, pkgs, ... }: {
  # Keep the workstation's interactive shell explicit. The generic modules
  # remain reusable in lightweight, recovery, and non-Hyprland profiles.
  desktop.enable = true;
  desktop.noctalia.enable = true;
  # Night light stays in the compositor. The physical ASUS display exposes
  # brightness through DDC/CI, so Noctalia can use the ddcutil package and the
  # active-seat I2C access supplied by the NixOS hardware profile.
  desktop.noctalia = {
    nightLight.enable = true;
    brightness = {
      enable = true;
      enableDdcutil = true;
    };
  };
  desktop.bar.networkCommand = "iwgtk";
  desktop.applications.networkBackend = "iwd";
  desktop.applications.sessionLauncher = "uwsm app --";
  desktop.workflow.terminalCommand = "uwsm app -- ${lib.getExe pkgs.ghostty}";

  # Noctalia already shows the active network and opens iwgtk on demand. Hide
  # iwgtk's separate status-notifier autostart without removing the app.
  xdg.configFile."autostart/iwgtk-indicator.desktop".text = ''
    [Desktop Entry]
    Hidden=true
  '';

  # Source selection is declarative. NASA's Image and Video Library has
  # curated mission photography; SVS remains available as an opt-in source
  # for users who specifically want scientific visualisations.
  desktop.wallpaper.enable = true;
  desktop.wallpaper.sources.nasaSvs.enable = false;
  desktop.wallpaper.sources.nasaImageLibrary.enable = true;
  desktop.wallpaper.sources.clevelandMuseum.enable = true;
  desktop.wallpaper.sources.wikimediaCommons.enable = true;
  desktop.wallpaper.sources.smithsonian.enable = true;
}
