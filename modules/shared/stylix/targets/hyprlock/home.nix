{
  homeManager =
    {
      config,
      lib,
      myLib,
      pkgs,
      osConfig ? null,
      ...
    }:
    let
      cfg = config.stylix.targets.hyprlock;
      colors = config.lib.stylix.colors;
      design = (import ../authentication/design.nix).render { inherit config; };
      # Greeter dimensions are logical pixels; Hyprlock uses physical pixels
      # and Pango points. Match the configured login output's desktop scale.
      outputScale =
        if osConfig == null then
          1
        else
          osConfig.services.displayManager.noctalia-greeter.settings.output.scale or 1;
      pixels = value: builtins.floor (value * outputScale + 0.5);
      physical = value: value * outputScale;
      points = value: builtins.floor (value * outputScale * 0.75 + 0.5);
      # Pango markup retains fractional point sizes that font_size rounds away.
      sizedText =
        size: text:
        ''<span size="${
          toString (builtins.floor (size * outputScale * 0.75 * 1024 + 0.5))
        }">${text}</span>'';
      cardBorder = pixels design.borderWidth;
      focusBorder = pixels design.focusWidth;
      # Hyprlang treats a single hash as a comment, including inside markup.
      passwordHint = sizedText design.fontSizes.body ''<span foreground="#${design.greeterPalette.on_surface}">Type password</span>'';
      avatarSvg = pkgs.writeText "authentication-user.svg" (
        myLib.templates.renderText ./scripts/user-icon.svg { design_colors_base05 = design.colors.base05; }
      );
      # Hyprlock's path loader does not supply the size required for SVGs.
      # Rasterize once in the build, keeping image decoding at lock time tiny.
      avatar = pkgs.runCommand "authentication-user.png" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
        rsvg-convert --width ${toString (pixels 64)} --height ${toString (pixels 64)} \
          ${avatarSvg} --output "$out"
      '';
      label = text: size: y: {
        monitor = "";
        text = sizedText size text;
        font_family = design.font;
        font_size = points size;
        color = "rgb(${colors.base05})";
        position = "0, ${toString (physical y)}";
        halign = "center";
        valign = "center";
      };
      clockLabel =
        format: size: y:
        (label "" size y)
        // {
          text = "cmd[update:60000] ${lib.getExe' pkgs.coreutils "date"} ${lib.escapeShellArg "+${sizedText size format}"}";
        };

    in
    {
      key = "nix-conf/stylix/hyprlock/homeManager";
      imports = [ (import ../../profile.nix).homeManager ];
      _file = __curPos.file;
      options.stylix.targets.hyprlock.custom.enable =
        lib.mkEnableOption "the desktop Hyprlock styling"
        // {
          default = true;
        };
      config =
        lib.mkIf
          (config.stylix.enable && cfg.enable && cfg.custom.enable && config.programs.hyprlock.enable)
          {
            programs.hyprlock.settings = {
              background.monitor = "";
              shape = [
                {
                  monitor = "";
                  # Hyprlock adds borders outside its configured fill rectangle.
                  size = "${toString (physical design.panelWidth - 2 * cardBorder)}, ${
                    toString (physical design.panelHeight - 2 * cardBorder)
                  }";
                  rounding = pixels design.panelRadius - cardBorder;
                  color = "rgb(${colors.base01})";
                  border_color = "rgb(${colors.base03})";
                  border_size = cardBorder;
                  position = "0, 0";
                  halign = "center";
                  valign = "center";
                }

              ];
              image = [
                {
                  monitor = "";
                  path = toString avatar;
                  size = pixels 64;
                  border_size = 0;
                  rounding = 0;
                  position = "0, ${toString (physical design.avatarY)}";
                  halign = "center";
                  valign = "center";
                }
              ];
              "input-field" = {
                monitor = "";
                size = "${toString (physical (design.panelWidth - 2 * design.padding) - 2 * focusBorder)}, ${
                  toString (physical design.inputHeight - 2 * focusBorder)
                }";
                rounding = pixels design.inputRadius - focusBorder;
                outline_thickness = focusBorder;
                dots_size = 0.2;
                dots_spacing = 0.2;
                dots_center = true;
                hide_input = false;
                fade_on_empty = false;
                placeholder_text = passwordHint;
                check_text = sizedText design.fontSizes.body "Checking password";
                fail_text = sizedText design.fontSizes.body "Authentication failed";
                capslock_color = "rgb(${colors.base0C})";
                check_color = lib.mkIf cfg.colors.enable (lib.mkForce "rgb(${colors.base0C})");
                position = "0, ${toString (physical design.inputY)}";
                halign = "center";
                valign = "center";
                outer_color = lib.mkIf cfg.colors.enable (lib.mkForce "rgb(${colors.base0C})");
                inner_color = lib.mkIf cfg.colors.enable (lib.mkForce "rgb(${colors.base00})");
                font_family = design.font;
              };
              label = [
                (clockLabel design.timeFormat design.fontSizes.clock design.clockY)
                (clockLabel design.dateFormat design.fontSizes.body design.dateY)
                (label "<b>$USER</b>" design.fontSizes.title design.accountY)
                (label "Press Enter to unlock" design.fontSizes.body design.footerY)
                (label "$LAYOUT" design.fontSizes.caption design.keyboardY)
              ];
            };
          };
    };
}
