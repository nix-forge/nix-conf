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
    src = ./scripts/screenshot.sh.in;
    dir = "bin";
    replacements = {
      grimblast = lib.getExe grimblastRegion;
    };
  };
  annotate = writeBashTemplate {
    name = "desktop-screenshot-annotate";
    src = ./scripts/screenshot-annotate.sh.in;
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
          lib.mkAfter [
            (hyprBind "PRINT" (lib.getExe' screenshot "desktop-screenshot"))
            (hyprBind "SUPER + PRINT" "${lib.getExe' screenshot "desktop-screenshot"} full")
            (hyprBind "SUPER + SHIFT + PRINT" (lib.getExe' screenshot "desktop-screenshot"))
          ]
        );
  };
}
