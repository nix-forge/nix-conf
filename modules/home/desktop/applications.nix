{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.applications;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  graphicalCommand =
    command: lib.optionalString (cfg.sessionLauncher != null) "${cfg.sessionLauncher} " + command;
  hyprBind = key: command: {
    _args = [
      key
      (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON command})")
    ];
  };
in
{
  options.desktop.applications = {
    enable = lib.mkEnableOption "desktop applications and device-management front ends";

    networkBackend = lib.mkOption {
      type = lib.types.enum [
        "networkmanager"
        "iwd"
        "none"
      ];
      default = "networkmanager";
      description = "Network UI to install for the host's chosen network stack.";
    };

    sessionLauncher = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "uwsm app --";
      description = ''
        Optional prefix for long-lived graphical applications. Set this to
        `uwsm app --` when UWSM owns the graphical session, so application
        lifetimes are represented by user units instead of compositor child
        processes.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "desktop.applications is supported on Linux only.";
      }
    ];

    # The corresponding NixOS services belong in `desktop-envs-interactive`.
    # The applications remain useful in a standalone Home Manager profile as
    # long as its host provides the conventional D-Bus services.
    home.packages = [
      pkgs.nautilus
      pkgs.file-roller
      pkgs.blueman
      pkgs.pwvucontrol
      pkgs.pavucontrol
      pkgs.playerctl
    ]
    ++ lib.optionals (cfg.networkBackend == "networkmanager") [ pkgs.networkmanagerapplet ]
    ++ lib.optionals (cfg.networkBackend == "iwd") [ pkgs.iwgtk ];

    # Blueman ships an XDG autostart entry for its tray applet. Ironbar owns
    # the desktop Bluetooth indicator, so shadow that entry without removing
    # Blueman Manager, which remains available for pairing and device setup.
    xdg.configFile."autostart/blueman.desktop".text = ''
      [Desktop Entry]
      Hidden=true
    '';

    wayland.windowManager.hyprland.settings.bind =
      lib.mkIf config.wayland.windowManager.hyprland.enable
        (lib.mkAfter [ (hyprBind "SUPER + E" (graphicalCommand (lib.getExe pkgs.nautilus))) ]);

    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "inode/directory" = [ "org.gnome.Nautilus.desktop" ];
        "application/x-gnome-saved-search" = [ "org.gnome.Nautilus.desktop" ];
      };
    };
  };
}
