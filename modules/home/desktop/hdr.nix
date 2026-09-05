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
        "auto"
        "srgb"
        "wide"
        "hdr"
        "hdredid"
      ];
      default = "auto";
      description = "Normal desktop color-management preset. Auto selects sRGB at 8 bpc and wide gamut at 10 bpc; the HDR presets force a PQ desktop.";
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

    autoHdr = lib.mkOption {
      type = lib.types.enum [
        0
        1
        2
      ];
      default = 1;
      description = "Hyprland fullscreen HDR switching: 0 disables it, 1 uses BT.2020 primaries, and 2 uses EDID primaries.";
    };

    vrr = lib.mkOption {
      type = lib.types.enum [
        (-1)
        0
        1
        2
        3
      ];
      default = 2;
      description = "Per-output VRR policy. Mode 2 limits VRR to fullscreen windows, avoiding refresh-rate flicker during ordinary OLED desktop use without depending on client content-type hints.";
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

    # Keep the ordinary desktop in Hyprland's recommended 10-bit automatic
    # color mode. Fullscreen clients that declare HDR content temporarily
    # switch the output to PQ, while VRR stays off for ordinary desktop work
    # where OLED brightness fluctuations are most distracting.
    # The display-scaling module emits the geometry rule first. Hyprland's Lua
    # API replaces an earlier rule with the same output selector, so keep this
    # complete color-aware rule last.
    wayland.windowManager.hyprland.settings.monitor = lib.mkOrder 1600 [
      {
        inherit (cfg) output;
        inherit (cfg) mode;
        inherit (cfg) position;
        inherit (cfg) scale;
        bitdepth = 10;
        cm = cfg.colorManagement;
        inherit (cfg) vrr;
        sdrbrightness = cfg.sdrBrightness;
        sdrsaturation = cfg.sdrSaturation;
      }
    ];

    # Hyprland removed cm_fs_passthrough in 0.55. Automatic HDR now owns the
    # fullscreen transition and passthrough decision.
    wayland.windowManager.hyprland.settings.config.render.cm_auto_hdr = cfg.autoHdr;
  };
}
