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
      # Bitwarden supplies a blue tray bitmap. Use Papirus's monochrome shield.
      trayOverrides.Bitwarden = "bitwarden-tray";
      # Use Discord's monochrome glyph for Vesktop's tray bitmap.
      trayOverrides.Vesktop = "discord-tray";
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

  # Bound Zen's main process and content children together. On this 30 GiB
  # host, an unbounded browser exhausted RAM and swap and the global OOM
  # killer selected unrelated desktop applications. Match UWSM's escaped
  # executable name so the policy survives new application scope IDs.
  # Keep surviving browser processes running if a content process hits the
  # ceiling; this cannot preserve a process selected directly by the kernel.
  xdg.configFile."systemd/user/app-Hyprland-zen\\x2dbeta-.scope.d/50-memory-budget.conf".text = ''
    [Scope]
    MemoryHigh=12G
    MemoryMax=16G
    MemorySwapMax=4G
    OOMPolicy=continue
  '';

  # ChatGPT splits its processes between Chromium and UWSM scopes. Preserve
  # surviving processes after an OOM victim in either group. Chromium uses
  # the first prefix too, so it receives the same behavior.
  xdg.configFile."systemd/user/app-org.chromium.Chromium-.scope.d/50-oom-policy.conf".text = ''
    [Scope]
    OOMPolicy=continue
  '';
  xdg.configFile."systemd/user/app-Hyprland-chatgpt-.scope.d/50-oom-policy.conf".text = ''
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
