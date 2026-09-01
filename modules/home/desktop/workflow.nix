{ config, lib, ... }:
let
  cfg = config.desktop.workflow;
  lua = lib.generators.mkLuaInline;
  bind = key: dispatcher: {
    _args = [
      key
      (lua dispatcher)
    ];
  };
  directionalBindings =
    lib.concatMap
      (
        direction:
        let
          focus = "hl.dsp.focus({ direction = ${builtins.toJSON direction.hyprland} })";
          move = "hl.dsp.window.move({ direction = ${builtins.toJSON direction.hyprland} })";
        in
        [
          (bind "SUPER + ${direction.key}" focus)
          (bind "SUPER + ${direction.arrow}" focus)
          (bind "SUPER + SHIFT + ${direction.key}" move)
          (bind "SUPER + SHIFT + ${direction.arrow}" move)
        ]
      )
      [
        {
          key = "H";
          arrow = "LEFT";
          hyprland = "l";
        }
        {
          key = "J";
          arrow = "DOWN";
          hyprland = "d";
        }
        {
          key = "K";
          arrow = "UP";
          hyprland = "u";
        }
        {
          key = "L";
          arrow = "RIGHT";
          hyprland = "r";
        }
      ];
  workspaceBindings = lib.concatMap (
    workspace:
    let
      key = if workspace == 10 then "0" else toString workspace;
      workspaceId = toString workspace;
    in
    [
      (bind "SUPER + ${key}" "hl.dsp.focus({ workspace = ${builtins.toJSON workspaceId} })")
      (bind "SUPER + SHIFT + ${key}" "hl.dsp.window.move({ workspace = ${builtins.toJSON workspaceId}, follow = false })")
    ]
  ) (lib.range 1 cfg.workspaceCount);
in
{
  options.desktop.workflow = {
    enable = lib.mkEnableOption "a predictable Hyprland keyboard and pointer workflow";

    workspaceCount = lib.mkOption {
      type = lib.types.ints.between 1 10;
      default = 10;
      description = "Number of numbered workspaces exposed through SUPER+1 through SUPER+0.";
    };

    terminalCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "uwsm app -- ghostty";
      description = "Optional long-lived terminal command for SUPER+SHIFT+RETURN.";
    };
  };

  config = lib.mkIf cfg.enable {
    wayland.windowManager.hyprland.settings.bind =
      lib.mkIf config.wayland.windowManager.hyprland.enable
        (
          lib.mkAfter (
            [
              (bind "SUPER + Q" "hl.dsp.window.close()")
              (bind "SUPER + F" "hl.dsp.window.fullscreen({ action = \"toggle\" })")
              (bind "SUPER + SHIFT + SPACE" "hl.dsp.window.float({ action = \"toggle\" })")
              (bind "SUPER + mouse:272" "hl.dsp.window.drag()")
              (bind "SUPER + mouse:273" "hl.dsp.window.resize()")
            ]
            ++ lib.optional (cfg.terminalCommand != null) (
              bind "SUPER + SHIFT + RETURN" "hl.dsp.exec_cmd(${builtins.toJSON cfg.terminalCommand})"
            )
            ++ directionalBindings
            ++ workspaceBindings
          )
        );
  };
}
