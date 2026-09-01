{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.capture;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  picturesDirectory = config.xdg.userDirs.pictures;
  screenshot = pkgs.replaceVarsWith {
    name = "desktop-screenshot";
    src = ./scripts/screenshot.sh.in;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      outputDirectory = "${picturesDirectory}/Screenshots";
      mkdir = lib.getExe' pkgs.coreutils "mkdir";
      date = lib.getExe' pkgs.coreutils "date";
      grim = lib.getExe pkgs.grim;
      slurp = lib.getExe pkgs.slurp;
      wlCopy = lib.getExe' pkgs.wl-clipboard "wl-copy";
    };
  };
  annotate = pkgs.replaceVarsWith {
    name = "desktop-screenshot-annotate";
    src = ./scripts/screenshot-annotate.sh.in;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      outputDirectory = "${picturesDirectory}/Screenshots";
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
  options.desktop.capture.enable = lib.mkEnableOption "portal-safe screenshots, recording, and streaming tools";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "desktop.capture is supported on Linux only.";
      }
      {
        assertion = config.xdg.userDirs.enable;
        message = "desktop.capture requires xdg.userDirs so it can save screenshots predictably.";
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
    wayland.windowManager.hyprland.settings.bind =
      lib.mkIf config.wayland.windowManager.hyprland.enable
        (
          lib.mkAfter [
            (hyprBind "PRINT" (lib.getExe' screenshot "desktop-screenshot"))
            (hyprBind "SUPER + PRINT" "${lib.getExe' screenshot "desktop-screenshot"} full")
            (hyprBind "SUPER + SHIFT + PRINT" (lib.getExe' annotate "desktop-screenshot-annotate"))
          ]
        );
  };
}
