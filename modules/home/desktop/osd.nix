{
  config,
  lib,
  myLib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  writeBashTemplate = myLib.writers.writeBashTemplate { inherit pkgs; };
  cfg = config.desktop.osd;
  hyprlandPackage = myLib.desktop.resolveHyprlandPackage { inherit config pkgs osConfig; };
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  client = lib.getExe' pkgs.swayosd "swayosd-client";
  focusedClient = writeBashTemplate {
    name = "desktop-swayosd-focused";
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      # SwayOSD otherwise mirrors feedback onto every connected output. Querying the
      # focused Hyprland output keeps a future multi-monitor desktop calm while the
      # fallback preserves useful feedback during compositor startup.
      monitor=""
      if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        monitor="$("@hyprctl@" monitors -j 2>/dev/null | "@jq@" -r '.[] | select(.focused == true) | .name' 2>/dev/null || true)"
      fi

      if [ -n "$monitor" ]; then
        exec "@swayosdClient@" --monitor "$monitor" "$@"
      fi

      exec "@swayosdClient@" "$@"
    '';
    dir = "bin";
    replacements = {
      hyprctl = lib.getExe' hyprlandPackage "hyprctl";
      jq = lib.getExe pkgs.jq;
      swayosdClient = client;
    };
  };
  targetedClient =
    if cfg.targetFocusedMonitor && config.wayland.windowManager.hyprland.enable then
      lib.getExe' focusedClient "desktop-swayosd-focused"
    else
      client;
  hyprBind = key: command: {
    _args = [
      key
      (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON command})")
    ];
  };
in
{
  options.desktop.osd = {
    enable = lib.mkEnableOption "SwayOSD for volume, brightness, and media feedback";

    targetFocusedMonitor = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Show OSD feedback only on Hyprland's focused output. Outside Hyprland,
        or before an output is available, SwayOSD falls back to its normal
        all-output behavior.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "desktop.osd is supported on Linux only.";
      }
    ];

    home.packages = [
      pkgs.brightnessctl
      pkgs.playerctl
      pkgs.swayosd
    ]
    ++ lib.optional (
      cfg.targetFocusedMonitor && config.wayland.windowManager.hyprland.enable
    ) focusedClient;

    xdg.configFile = {
      "swayosd/config.toml".source = (pkgs.formats.toml { }).generate "swayosd-config.toml" {
        server = {
          min_brightness = 5;
          show_percentage = true;
          max_volume = 100;
          keyboard_backlight = false;
          top_margin = 0.85;
        }
        // lib.optionalAttrs (config.xdg.configFile ? "swayosd/style.css") {
          style = "${config.xdg.configHome}/swayosd/style.css";
        };
      };

    };

    systemd.user.services.swayosd = {
      Unit = {
        Description = "SwayOSD server";
        PartOf = [ "graphical-session.target" ];
        After = [
          "graphical-session.target"
          "pipewire.service"
        ];
      };
      Service = {
        ExecStart = "${lib.getExe' pkgs.swayosd "swayosd-server"}";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # Hardware media keys should behave like an ordinary desktop even when no
    # panel is visible. These bindings remain additive to a host's own layout.
    wayland.windowManager.hyprland.settings.bind =
      lib.mkIf config.wayland.windowManager.hyprland.enable
        (
          lib.mkAfter [
            (hyprBind "XF86AudioRaiseVolume" "${targetedClient} --output-volume raise")
            (hyprBind "XF86AudioLowerVolume" "${targetedClient} --output-volume lower")
            (hyprBind "XF86AudioMute" "${targetedClient} --output-volume mute-toggle")
            (hyprBind "XF86AudioMicMute" "${targetedClient} --input-volume mute-toggle")
            (hyprBind "XF86MonBrightnessUp" "${targetedClient} --brightness raise")
            (hyprBind "XF86MonBrightnessDown" "${targetedClient} --brightness lower")
            (hyprBind "XF86AudioPlay" "${targetedClient} --playerctl play-pause")
            (hyprBind "XF86AudioNext" "${targetedClient} --playerctl next")
            (hyprBind "XF86AudioPrev" "${targetedClient} --playerctl previous")
          ]
        );
  };
}
