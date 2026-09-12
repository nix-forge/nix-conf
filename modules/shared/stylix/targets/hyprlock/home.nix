{
  homeManager =
    {
      config,
      lib,
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
      avatarSvg = pkgs.writeText "authentication-user.svg" ''
        <svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24"
              fill="none" stroke="${design.colors.base05}" stroke-width="2"
              stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="7" r="4"/>
          <path d="M6 21v-2a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v2"/>
        </svg>
      '';
      # Hyprlock's path loader does not supply the size required for SVGs.
      # Rasterize once in the build, keeping image decoding at lock time tiny.
      avatar = pkgs.runCommand "authentication-user.png" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
        rsvg-convert --width ${toString (pixels 64)} --height ${toString (pixels 64)} \
          ${avatarSvg} --output "$out"
      '';
      submitX = design.panelWidth / 2 - design.padding - design.inputHeight / 2;
      inputX = -(design.inputHeight + design.gap) / 2;
      arrow =
        color:
        let
          svg = pkgs.writeText "authentication-submit.svg" ''
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24"
                  fill="none" stroke="${color}" stroke-width="2"
                  stroke-linecap="round" stroke-linejoin="round">
              <path d="M5 12h14m-6-6 6 6-6 6"/>
            </svg>
          '';
        in
        pkgs.runCommand "authentication-submit.png" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
          rsvg-convert --width ${toString (pixels 16)} --height ${toString (pixels 16)} \
            ${svg} --output "$out"
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
                {
                  monitor = "";
                  size = "${toString (pixels design.inputHeight)}, ${toString (pixels design.inputHeight)}";
                  rounding = pixels design.inputRadius;
                  color = "rgb(${colors.base0D})";
                  border_size = 0;
                  position = "${toString (physical submitX)}, ${toString (physical design.inputY)}";
                  halign = "center";
                  valign = "center";
                  # Native password submission keeps the same PAM and busy guards
                  # as Enter. The control owns both its fill and arrow state.
                  submit_input = true;
                  submit_icon = toString (arrow design.greeterPalette.on_primary);
                  submit_icon_hover = toString (arrow design.greeterPalette.on_hover);
                  submit_icon_size = pixels 16;
                  submit_hover_color = "rgb(${colors.base02})";
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
                size = "${
                  toString (
                    physical (design.panelWidth - 2 * design.padding - design.gap - design.inputHeight)
                    - 2 * focusBorder
                  )
                }, ${toString (physical design.inputHeight - 2 * focusBorder)}";
                rounding = pixels design.inputRadius - focusBorder;
                outline_thickness = focusBorder;
                dots_size = 0.2;
                dots_spacing = 0.2;
                dots_center = false;
                text_align = "left";
                padding_x = pixels design.inputPadding - focusBorder;
                hide_input = false;
                fade_on_empty = false;
                placeholder_text = passwordHint;
                check_text = passwordHint;
                check_opacity = 0.55;
                fail_text = passwordHint;
                capslock_color = "rgb(${colors.base0C})";
                check_color = lib.mkIf cfg.colors.enable (lib.mkForce "rgb(${colors.base0C})");
                position = "${toString (physical inputX)}, ${toString (physical design.inputY)}";
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
                (label "$AUTHCHECK" design.fontSizes.caption design.statusY)
                (
                  (label "$AUTHFAIL" design.fontSizes.caption design.statusY) // { color = "rgb(${colors.base08})"; }
                )
                (
                  (label "$LAYOUT$CAPSLOCK" design.fontSizes.caption design.keyboardY)
                  // {
                    capslock_color = "rgb(${colors.base08})";
                  }
                )
              ];
            };
          };
    };
}
