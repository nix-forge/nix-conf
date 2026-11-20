{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  writeBashTemplate = myLib.writers.writeBashTemplate { inherit pkgs; };
  cfg = config.desktop.capture;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  grimblastRegion = pkgs.grimblast-region;
  screenshot = writeBashTemplate {
    name = "desktop-screenshot";
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      if [ "$#" -gt 0 ] && [ "$1" = "full" ]; then
        exec @grimblast@ copy screen
      else
        # Supply no window rectangles, so clicks cannot select an entire window.
        export SLURP_RECTS='''
        # Slurp's default translucent white background flashes the whole display.
        export SLURP_ARGS='-b 00000000 -B 00000000 -c ffffffff -w 2'
        # Freeze before selection so moving content stays at the captured frame.
        exec @grimblast@ --freeze copy area
      fi
    '';
    dir = "bin";
    replacements = {
      grimblast = lib.getExe grimblastRegion;
    };
  };
  annotate = writeBashTemplate {
    name = "desktop-screenshot-annotate";
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      umask 077
      # Configuration values are shell-escaped literals, including dollar signs.
      # shellcheck disable=SC2016
      output_directory=@outputDirectory@
      @mkdir@ -p -- "$output_directory"
      timestamp="$(@date@ +%Y-%m-%d_%H-%M-%S)"
      @grim@ -g "$(@slurp@)" -t ppm - | @satty@ --filename - --fullscreen \
        --output-filename "$output_directory/$timestamp.png" \
        --copy-command @wlCopy@
    '';
    dir = "bin";
    replacements = {
      outputDirectory = lib.escapeShellArg cfg.directory;
      mkdir = lib.getExe' pkgs.coreutils "mkdir";
      date = lib.getExe' pkgs.coreutils "date";
      grim = lib.getExe pkgs.grim;
      slurp = lib.getExe pkgs.slurp;
      satty = lib.getExe pkgs.satty;
      wlCopy = lib.getExe' pkgs.wl-clipboard "wl-copy";
    };
  };
  hyprBind = key: command: {
    _args = [
      key
      (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON command})")
    ];
  };
in
{
  options.desktop.capture = {
    enable = lib.mkEnableOption "portal-safe screenshots, recording, and streaming tools";
    directory = lib.mkOption {
      type = lib.types.str;
      default = "${
        if config.xdg.userDirs.pictures != null then
          config.xdg.userDirs.pictures
        else
          "${config.home.homeDirectory}/Pictures"
      }/Screenshots";
      defaultText = "The configured XDG Pictures directory, falling back to ~/Pictures, plus /Screenshots.";
      description = "Directory for annotated screenshots, independent of whether XDG user directories are managed.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "desktop.capture is supported on Linux only.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.directory;
        message = "desktop.capture.directory must be an absolute path.";
      }
    ];

    home.packages = [
      pkgs.grim
      pkgs.slurp
      pkgs.satty
      pkgs.wl-clipboard
      pkgs.obs-studio
      pkgs.wf-recorder
      screenshot
      annotate
    ];

    # OBS uses the desktop portal and PipeWire source picker. No compositor
    # plugin is installed, so capture remains outside Hyprland's process.
    wayland.windowManager.hyprland.settings.layer_rule =
      lib.mkIf config.wayland.windowManager.hyprland.enable
        [
          {
            match.namespace = "^(hyprpicker|selection)$";
            no_anim = true;
          }
        ];

    wayland.windowManager.hyprland.settings.bind =
      lib.mkIf config.wayland.windowManager.hyprland.enable
        (
          lib.mkAfter (
            [
              (hyprBind "PRINT" (lib.getExe' screenshot "desktop-screenshot"))
              (hyprBind "SUPER + PRINT" "${lib.getExe' screenshot "desktop-screenshot"} full")
              (hyprBind "SUPER + SHIFT + PRINT" (lib.getExe' screenshot "desktop-screenshot"))
            ]
            ++ lib.optionals (config.keyboard.macosShortcuts.enable or false) [
              (hyprBind "SUPER + SHIFT + 3" "${lib.getExe' screenshot "desktop-screenshot"} full")
              (hyprBind "SUPER + SHIFT + 4" (lib.getExe' screenshot "desktop-screenshot"))
            ]
          )
        );
  };
}
