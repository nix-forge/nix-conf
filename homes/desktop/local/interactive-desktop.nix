{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Keep the workstation's interactive shell explicit. The generic modules
  # remain reusable in lightweight, recovery, and non-Hyprland profiles.
  desktop.enable = true;
  desktop.noctalia.enable = true;
  # Night light stays in the compositor. The physical ASUS display exposes
  # brightness through DDC/CI, so Noctalia can use the ddcutil package and the
  # active-seat I2C access supplied by the NixOS hardware profile.
  desktop.noctalia = {
    dock = {
      enable = true;
      # Follow homes/macbook-pro-m4/local/dock.nix in the same order, using
      # installed Linux counterparts for Finder, Messages, Calendar, Preview
      # and Activity Monitor. Apple-only services do not get dead shortcuts.
      pinned = [
        "org.gnome.Nautilus"
        "com.mitchellh.ghostty"
        "code"
        "chatgpt"
        "zen-beta"
        "signal"
        "vesktop"
        "spotify"
        "org.gnome.Calendar"
        "org.gnome.Papers"
        "noctalia-settings"
        "org.gnome.SystemMonitor"
      ];
    };
    darkAppIcons.enable = true;
    symbolicBarIcons = {
      enable = true;
      # ChatGPT sends a static app bitmap without a theme icon name. Limit the
      # override to this known case so other tray pixmaps retain their badges.
      trayOverrides.ChatGPT = "indicator-chatgpt";
    };
    nightLight = {
      enable = true;
      dayTemperature = 6500;
      # Noctalia's blue gamma table reaches zero at 1900 K. See
      # docs/night-light-sleep-evidence.md for the evidence and limitations.
      nightTemperature = 1900;
      # The one-hour fade finishes at 20:00, three hours before a 23:00
      # bedtime. The existing morning fade finishes at 07:00.
      sunset = "19:30";
      sunrise = "06:30";
    };
    brightness = {
      enable = true;
      enableDdcutil = true;
    };
  };
  desktop.bar.networkCommand = "iwgtk";
  desktop.applications.networkBackend = "iwd";
  desktop.applications.sessionLauncher = "uwsm app --";
  desktop.workflow.terminalCommand = "uwsm app -- ${lib.getExe pkgs.ghostty}";

  # ChatGPT's Chromium runtime moves the app and its task processes into
  # app-org.chromium.Chromium-<pid>.scope. With the default OOMPolicy=stop,
  # one killed Nix evaluator also terminates the GUI and every other task.
  # Chromium uses the same scope prefix, so this applies to its scopes too.
  xdg.configFile."systemd/user/app-org.chromium.Chromium-.scope.d/50-oom-policy.conf".text = ''
    [Scope]
    OOMPolicy=continue
  '';

  xdg.dataFile."applications/noctalia-settings.desktop".source =
    let
      entry = pkgs.makeDesktopItem {
        name = "noctalia-settings";
        desktopName = "Desktop Settings";
        exec = "${lib.getExe config.programs.noctalia.package} msg settings-open";
        icon = "preferences-system";
        categories = [ "Settings" ];
        startupWMClass = "dev.noctalia.Noctalia";
      };
    in
    "${entry}/share/applications/noctalia-settings.desktop";

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
