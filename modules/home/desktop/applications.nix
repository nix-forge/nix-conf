{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.applications;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
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
      pkgs.thunar
      pkgs.file-roller
      pkgs.blueman
      pkgs.pwvucontrol
      pkgs.pavucontrol
      pkgs.playerctl
    ]
    ++ lib.optionals (cfg.networkBackend == "networkmanager") [ pkgs.networkmanagerapplet ]
    ++ lib.optionals (cfg.networkBackend == "iwd") [ pkgs.iwgtk ];

    wayland.windowManager.hyprland.settings.bind =
      lib.mkIf config.wayland.windowManager.hyprland.enable
        (lib.mkAfter [ (hyprBind "SUPER + E" (lib.getExe pkgs.thunar)) ]);
  };
}
