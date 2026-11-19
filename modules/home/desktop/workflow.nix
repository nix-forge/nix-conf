{ config, lib, ... }:
let
  macShortcuts = config.keyboard.macosShortcuts.enable or false;
  desktopMod = if macShortcuts then "CTRL + ALT" else "SUPER";
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
          (bind "${desktopMod} + ${direction.key}" focus)
          (bind "${desktopMod} + SHIFT + ${direction.key}" move)
        ]
        ++ lib.optionals (!macShortcuts) [
          (bind "${desktopMod} + ${direction.arrow}" focus)
          (bind "${desktopMod} + SHIFT + ${direction.arrow}" move)
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
  workspaceBindings =
    lib.concatMap (
      workspace:
      let
        key = if workspace == 10 then "0" else toString workspace;
        workspaceId = toString workspace;
      in
      [
        (bind "${desktopMod} + ${key}" "hl.dsp.focus({ workspace = ${builtins.toJSON workspaceId} })")
        (bind "${desktopMod} + SHIFT + ${key}" "hl.dsp.window.move({ workspace = ${builtins.toJSON workspaceId}, follow = false })")
      ]
    ) (lib.range 1 cfg.workspaceCount)
    ++ lib.concatLists (
      lib.mapAttrsToList (key: workspaceId: [
        (bind "${desktopMod} + ${key}" "hl.dsp.focus({ workspace = ${builtins.toJSON workspaceId} })")
        (bind "${desktopMod} + SHIFT + ${key}" "hl.dsp.window.move({ workspace = ${builtins.toJSON workspaceId}, follow = false })")
      ]) cfg.namedWorkspaces
    );
in
{
  options.desktop.workflow = {
    enable = lib.mkEnableOption "a predictable Hyprland keyboard and pointer workflow";

    workspaceCount = lib.mkOption {
      type = lib.types.ints.between 1 10;
      default = 10;
      description = "Numbered workspaces use the desktop modifier plus 1–9, with 0 for the tenth workspace.";
    };

    namedWorkspaces = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        B = "10";
      };
      description = "Additional workspace key-to-ID mappings, using the same desktop modifier.";
    };

    terminalCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "uwsm app -- ghostty";
      description = "Optional long-lived terminal command for the configured terminal shortcut.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          lib.intersectLists (map lib.toUpper (builtins.attrNames cfg.namedWorkspaces)) (
            [
              "H"
              "J"
              "K"
              "L"
              "Q"
              "F"
              "SPACE"
              "RETURN"
              "TAB"
            ]
            ++ map toString (lib.range 1 cfg.workspaceCount)
            ++ lib.optional (cfg.workspaceCount == 10) "0"
            ++ lib.optionals (!macShortcuts) [
              "LEFT"
              "RIGHT"
              "UP"
              "DOWN"
            ]
          ) == [ ];
        message = "desktop.workflow.namedWorkspaces must not reuse numbered workspace keys or window-management shortcuts.";
      }
    ];
    wayland.windowManager.hyprland.settings.bind =
      lib.mkIf config.wayland.windowManager.hyprland.enable
        (
          lib.mkAfter (
            [
              (bind "${desktopMod} + Q" "hl.dsp.window.close()")
              (bind (
                if macShortcuts then "${desktopMod} + SHIFT + F" else "SUPER + F"
              ) "hl.dsp.window.fullscreen({ action = \"toggle\" })")
              (bind "${desktopMod} + SHIFT + SPACE" "hl.dsp.window.float({ action = \"toggle\" })")
              (bind "${desktopMod} + mouse:272" "hl.dsp.window.drag()")
              (bind "${desktopMod} + mouse:273" "hl.dsp.window.resize()")
            ]
            ++ lib.optional (cfg.terminalCommand != null) (
              bind (
                if macShortcuts then "${desktopMod} + RETURN" else "SUPER + SHIFT + RETURN"
              ) "hl.dsp.exec_cmd(${builtins.toJSON cfg.terminalCommand})"
            )
            ++ lib.optionals macShortcuts [
              (bind "${desktopMod} + TAB" "hl.dsp.focus({ workspace = \"previous\" })")
            ]
            ++ directionalBindings
            ++ workspaceBindings
          )
        );
  };
}
