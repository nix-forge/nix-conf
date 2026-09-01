{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.osd;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  colors = config.lib.stylix.colors.withHashtag;
  client = lib.getExe' pkgs.swayosd "swayosd-client";
  focusedClient = pkgs.replaceVarsWith {
    name = "desktop-swayosd-focused";
    src = ./scripts/swayosd-focused.sh.in;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      hyprctl = lib.getExe' pkgs.hyprland "hyprctl";
      jq = lib.getExe pkgs.jq;
      swayosdClient = client;
    };
  };
  targetedClient =
    if cfg.targetFocusedMonitor then lib.getExe' focusedClient "desktop-swayosd-focused" else client;
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
      focusedClient
    ];

    xdg.configFile = {
      "swayosd/config.toml".source = pkgs.replaceVarsWith {
        name = "swayosd-config";
        src = ./config/swayosd.toml.in;
        replacements.stylePath = "${config.xdg.configHome}/swayosd/style.css";
      };

      "swayosd/style.css".source = pkgs.replaceVarsWith {
        name = "swayosd-style";
        src = ./config/swayosd-style.css.in;
        replacements = {
          font = builtins.toJSON config.stylix.fonts.sansSerif.name;
          inherit (colors)
            base00
            base03
            base05
            base0D
            ;
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
