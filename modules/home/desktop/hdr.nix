{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.hdr;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  options.desktop.hdr = {
    enable = lib.mkEnableOption "an opt-in Hyprland HDR monitor profile";

    output = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "DP-1";
      description = "Physical HDR monitor connector reported by `hyprctl monitors`. Virtual Sunshine outputs are intentionally unsupported.";
    };

    mode = lib.mkOption {
      type = lib.types.str;
      default = "3840x2160@120";
      description = "Physical monitor mode. Use a mode exposed by the monitor EDID and GPU driver.";
    };

    position = lib.mkOption {
      type = lib.types.str;
      default = "0x0";
      description = "Hyprland monitor position.";
    };

    scale = lib.mkOption {
      type = lib.types.numbers.positive;
      default = 1.0;
      description = "Hyprland output scale for the physical HDR monitor.";
    };

    colorManagement = lib.mkOption {
      type = lib.types.enum [
        "hdr"
        "hdredid"
      ];
      default = "hdr";
      description = "Hyprland's experimental PQ HDR color-management preset. Choose hdredid only when the monitor's EDID HDR metadata is known to be correct.";
    };

    sdrBrightness = lib.mkOption {
      type = lib.types.numbers.between 1.0 2.0;
      default = 1.2;
      description = "SDR reference brightness while the monitor is in HDR mode. Hyprland documents 1.0 to 2.0 as the typical range.";
    };

    sdrSaturation = lib.mkOption {
      type = lib.types.numbers.between 0.5 1.5;
      default = 1.0;
      description = "SDR saturation correction while the monitor is in HDR mode.";
    };

    fullscreenPassthrough = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow color-managed HDR fullscreen clients to use Hyprland's experimental HDR passthrough path.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "desktop.hdr is supported on Linux only.";
      }
      {
        assertion = config.wayland.windowManager.hyprland.enable;
        message = "desktop.hdr requires the Hyprland module.";
      }
      {
        assertion = cfg.output != null && cfg.output != "";
        message = "desktop.hdr requires the physical connector name reported by hyprctl monitors.";
      }
      {
        assertion = cfg.output != "SUNSHINE";
        message = "desktop.hdr never enables HDR on the Sunshine virtual output because that capture path cannot transport HDR metadata.";
      }
    ];

    # Hyprland treats HDR output and color management as experimental. This
    # is deliberately an explicit physical-output profile rather than a
    # session-wide switch, so remote streaming stays SDR and stable.
    wayland.windowManager.hyprland.settings.monitor = lib.mkAfter [
      {
        inherit (cfg) output;
        inherit (cfg) mode;
        inherit (cfg) position;
        inherit (cfg) scale;
        bitdepth = 10;
        cm = cfg.colorManagement;
        supports_wide_color = 1;
        supports_hdr = 1;
        sdrbrightness = cfg.sdrBrightness;
        sdrsaturation = cfg.sdrSaturation;
      }
    ];

    wayland.windowManager.hyprland.settings.config.render = {
      cm_auto_hdr = 1;
      cm_fs_passthrough = if cfg.fullscreenPassthrough then 1 else 0;
    };
  };
}
