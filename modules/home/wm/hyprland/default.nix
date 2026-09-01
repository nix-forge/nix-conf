{
  config,
  pkgs,
  lib,
  osConfig ? null,
  ...
}:
let
  nixosHyprland = osConfig != null && (osConfig.programs.hyprland.enable or false);
  withUWSM = if nixosHyprland then osConfig.programs.hyprland.withUWSM else false;
  usingUWSMHyprland = nixosHyprland && withUWSM;

  cfg = config.wayland.windowManager.hyprland.displayScaling;
  cursorCfg = cfg.cursor;

  # Keep generated scales conventional and predictable. The associated ratio
  # also lets us reject scales that would create fractional logical pixels.
  scaleDefinitions = [
    {
      value = 1.0;
      numerator = 1;
      denominator = 1;
    }
    {
      value = 1.25;
      numerator = 5;
      denominator = 4;
    }
    {
      value = 1.5;
      numerator = 3;
      denominator = 2;
    }
    {
      value = 1.75;
      numerator = 7;
      denominator = 4;
    }
    {
      value = 2.0;
      numerator = 2;
      denominator = 1;
    }
  ];
  standardScales = map (definition: definition.value) scaleDefinitions;

  scaleDefinition =
    scale: lib.findFirst (definition: definition.value == scale) null scaleDefinitions;
  divisibleBy = dividend: divisor: builtins.div dividend divisor * divisor == dividend;
  validForResolution =
    resolution: scale:
    let
      definition = scaleDefinition scale;
    in
    divisibleBy (resolution.width * definition.denominator) definition.numerator
    && divisibleBy (resolution.height * definition.denominator) definition.numerator;
  distance = left: right: if left >= right then left - right else right - left;
  nearestScale =
    resolution: desired:
    let
      validScales = lib.filter (scale: validForResolution resolution scale) standardScales;
    in
    builtins.foldl' (
      nearest: candidate:
      if distance candidate desired < distance nearest desired then candidate else nearest
    ) (builtins.head validScales) (builtins.tail validScales);
  calculatedScale =
    display:
    let
      horizontalDpi = display.resolution.width * 25.4 / display.physicalSizeMm.width;
      verticalDpi = display.resolution.height * 25.4 / display.physicalSizeMm.height;
      averageDpi = (horizontalDpi + verticalDpi) / 2.0;
    in
    nearestScale display.resolution (averageDpi / cfg.referenceDpi);
  resolvedScale =
    display:
    if display.scale != null then
      display.scale
    else if display.physicalSizeMm != null then
      calculatedScale display
    # Preserve assertion reporting for an incomplete display declaration
    # instead of attempting DPI division on a null physical size.
    else
      1.0;
  maximum = left: right: if left > right then left else right;
  minimum = left: right: if left < right then left else right;
  clamp =
    lower: upper: value:
    maximum lower (minimum upper value);
  scaleForCursor =
    if cursorCfg.referenceOutput != null && builtins.hasAttr cursorCfg.referenceOutput cfg.displays then
      resolvedScale cfg.displays.${cursorCfg.referenceOutput}
    else
      builtins.foldl' (largest: display: maximum largest (resolvedScale display)) 1.0 (
        builtins.attrValues cfg.displays
      );
  derivedCursorSize = clamp cursorCfg.minimumSize cursorCfg.maximumSize (
    builtins.floor (cursorCfg.logicalSize * scaleForCursor + 0.5)
  );
  monitorRules = lib.mapAttrsToList (output: display: {
    inherit output;
    inherit (display) mode position;
    scale = resolvedScale display;
  }) cfg.displays;
in
{
  imports = [ (import ./xdg.nix { inherit nixosHyprland pkgs; }) ];

  options.wayland.windowManager.hyprland.displayScaling = {
    enable = lib.mkEnableOption "declarative, display-specific Hyprland scaling";

    referenceDpi = lib.mkOption {
      type = lib.types.ints.between 72 160;
      default = 96;
      description = ''
        Reference DPI used when deriving a scale from a display's pixel
        resolution and physical size. 96 DPI matches the CSS/desktop baseline.
      '';
    };

    displays = lib.mkOption {
      default = { };
      description = ''
        Per-output monitor rules. Each display must state its native pixel
        resolution so this module can ensure the chosen scale creates integral
        logical pixels. Choose either an explicit standard scale or physical
        dimensions in millimetres for deterministic DPI-based selection.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            mode = lib.mkOption {
              type = lib.types.str;
              default = "preferred";
              description = "Hyprland mode string, such as 2560x1440@144.";
            };

            position = lib.mkOption {
              type = lib.types.str;
              default = "auto";
              description = "Hyprland logical-layout position, such as auto or 0x0.";
            };

            resolution = {
              width = lib.mkOption {
                type = lib.types.ints.positive;
                description = "Native horizontal resolution in pixels.";
              };
              height = lib.mkOption {
                type = lib.types.ints.positive;
                description = "Native vertical resolution in pixels.";
              };
            };

            scale = lib.mkOption {
              type = lib.types.nullOr (lib.types.enum standardScales);
              default = null;
              example = 1.5;
              description = ''
                Explicit scale. Only conventional quarter-step scales from 1
                through 2 are accepted; null derives the nearest valid scale
                from physicalSizeMm and resolution.
              '';
            };

            physicalSizeMm = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.submodule {
                  options = {
                    width = lib.mkOption {
                      type = lib.types.ints.positive;
                      description = "Visible horizontal panel width in millimetres.";
                    };
                    height = lib.mkOption {
                      type = lib.types.ints.positive;
                      description = "Visible vertical panel height in millimetres.";
                    };
                  };
                }
              );
              default = null;
              example = {
                width = 597;
                height = 336;
              };
              description = ''
                Visible panel dimensions in millimetres. Set this instead of
                scale to derive a conventional scale from display DPI.
              '';
            };
          };
        }
      );
    };

    cursor = {
      enable = lib.mkEnableOption "display-scale-aware XCursor sizing";

      logicalSize = lib.mkOption {
        type = lib.types.ints.between 16 48;
        default = 24;
        description = ''
          Intended cursor size in logical pixels at scale 1. The generated
          XCursor size is this value multiplied by the selected display scale.
        '';
      };

      minimumSize = lib.mkOption {
        type = lib.types.ints.between 16 64;
        default = 16;
        description = "Smallest generated physical XCursor size in pixels.";
      };

      maximumSize = lib.mkOption {
        type = lib.types.ints.between 24 96;
        default = 64;
        description = "Largest generated physical XCursor size in pixels.";
      };

      resolvedSize = lib.mkOption {
        type = lib.types.ints.positive;
        readOnly = true;
        default = derivedCursorSize;
        description = ''
          Computed physical XCursor size in pixels. This is the logical size
          multiplied by the selected display scale and bounded by the minimum
          and maximum size options.
        '';
      };

      referenceOutput = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "eDP-1";
        description = ''
          Output whose scale determines the session-wide cursor size. Leave
          null to use the highest configured display scale, which avoids a
          soft cursor on a HiDPI display in a mixed-DPI layout.
        '';
      };
    };
  };

  config = {
    wayland.windowManager.hyprland = {
      enable = true;
      # Hyprland 0.55+ reads `hyprland.lua`.
      configType = "lua";
      # Use the NixOS-provided compositor and portal when embedded in NixOS;
      # otherwise use the matching Nixpkgs packages.  This repository does not
      # carry a separate Hyprland flake input.
      package = if nixosHyprland then null else pkgs.hyprland;
      portalPackage = if nixosHyprland then null else pkgs.xdg-desktop-portal-hyprland;

      systemd = {
        enable = lib.mkForce (!usingUWSMHyprland);
        variables = [ "--all" ];
      };

      settings.monitor = lib.mkIf cfg.enable (lib.mkAfter monitorRules);
    };

    # XCursor is shared by GTK, Qt, XWayland, Chromium, and legacy cursor
    # fallback in Hyprland. Keep the conventional logical size proportional to
    # the declared output scale instead of hard-coding a host-specific pixel
    # value. A theme module such as Stylix can consume cursor.resolvedSize
    # without making this portable module depend on a particular theming stack.
    home.pointerCursor.size = lib.mkIf (cfg.enable && cursorCfg.enable) (lib.mkForce derivedCursorSize);
    home.sessionVariables.XCURSOR_SIZE = lib.mkIf (cfg.enable && cursorCfg.enable) (
      lib.mkForce (toString derivedCursorSize)
    );

    # UWSM reads its own environment before starting Hyprland. Add both cursor
    # protocols' derived sizes to its generic environment so native Wayland,
    # XWayland, and legacy clients agree from the first process in the session.
    # Theme selection remains local: this portable module must not impose a
    # cursor package or theme name on every host.
    xdg.configFile."uwsm/env".text = lib.mkIf (usingUWSMHyprland && cfg.enable && cursorCfg.enable) (
      lib.mkAfter ''
        export XCURSOR_SIZE=${toString derivedCursorSize}
        export HYPRCURSOR_SIZE=${toString derivedCursorSize}
      ''
    );

    assertions = [
      {
        assertion = cfg.enable || cfg.displays == { };
        message = ''
          wayland.windowManager.hyprland.displayScaling.displays is set but
          displayScaling.enable is false.
        '';
      }
      {
        assertion = !cursorCfg.enable || cfg.enable;
        message = ''
          wayland.windowManager.hyprland.displayScaling.cursor.enable
          requires displayScaling.enable.
        '';
      }
      {
        assertion = !cursorCfg.enable || cfg.displays != { };
        message = ''
          wayland.windowManager.hyprland.displayScaling.cursor.enable
          requires at least one declared display.
        '';
      }
      {
        assertion =
          cursorCfg.referenceOutput == null || builtins.hasAttr cursorCfg.referenceOutput cfg.displays;
        message = ''
          Hyprland cursor reference output '${toString cursorCfg.referenceOutput}'
          is not declared in displayScaling.displays.
        '';
      }
      {
        assertion = cursorCfg.minimumSize <= cursorCfg.maximumSize;
        message = "Hyprland cursor minimumSize must not exceed maximumSize.";
      }
    ]
    ++ lib.concatMap (
      output:
      let
        display = cfg.displays.${output};
        scale = resolvedScale display;
      in
      [
        {
          assertion = display.scale != null || display.physicalSizeMm != null;
          message = ''
            Hyprland display '${output}' must set either scale or
            physicalSizeMm.
          '';
        }
        {
          assertion = display.scale == null || display.physicalSizeMm == null;
          message = ''
            Hyprland display '${output}' must use either an explicit scale or
            DPI-derived scaling, not both.
          '';
        }
        {
          assertion = validForResolution display.resolution scale;
          message = ''
            Hyprland display '${output}' scale ${toString scale} does not
            produce integral logical pixels for ${toString display.resolution.width}x${toString display.resolution.height}.
          '';
        }
      ]
    ) (builtins.attrNames cfg.displays);
  };
}
