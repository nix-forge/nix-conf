{
  pkgs,
  config,
  lib,
  ...
}:
{
  programs.rofi =
    let
      font = {
        name = "MonaspiceNe Nerd Font";
        size = toString 12;
      };
    in
    {
      enable = true;
      package = pkgs.rofi;

      location = "center";
      cycle = true;
      terminal = config.home.sessionVariables.TERMINAL;
      extraConfig = lib.mkForce {
        modes = "run,drun";
        icon-theme = config.gtk.iconTheme.name;
      };

      font = lib.mkForce "${font.name} ${font.size}";
      theme =
        let
          # Use `mkLiteral` for string-like values that should show without
          # quotes, e.g.:
          # {
          #   foo = "abc"; => foo: "abc";
          #   bar = mkLiteral "abc"; => bar: abc;
          # };
          inherit (config.lib.formats.rasi) mkLiteral;

          # Colors
          bg0 = mkLiteral "#242424E6";
          bg1 = mkLiteral "#7E7E7E80";
          bg2 = mkLiteral "#0860f2E6";

          fg0 = mkLiteral "#DEDEDE";
          fg1 = mkLiteral "#FFFFFF";
          fg2 = mkLiteral "#DEDEDE80";
        in
        lib.mkForce {
          # Theme from: https://github.com/newmanls/rofi-themes-collection
          # NOTE: some of the theme is set in the Nix options above

          "*" = {
            font = "${font.name} ${font.size}";

            background-color = mkLiteral "transparent";
            text-color = fg0;

            margin = mkLiteral "0";
            padding = mkLiteral "0";
            spacing = mkLiteral "0";
          };

          "window" = {
            background-color = bg0;

            width = mkLiteral "640";
            # border-radius = mkLiteral "8";
            border = mkLiteral "2px";
          };

          "inputbar" = {
            font = "${font.name} ${font.size}";
            padding = mkLiteral "12px";
            spacing = mkLiteral "12px";
            children = mkLiteral "[ icon-search, entry ]";
          };

          "icon-search" = {
            expand = mkLiteral "false";
            filename = "search";
            size = mkLiteral "28px";
          };

          "icon-search, entry, element-icon, element-text" = {
            vertical-align = mkLiteral "0.5";
          };

          "entry" = {
            font = mkLiteral "inherit";

            placeholder = "Search";
            placeholder-color = fg2;
          };

          "message" = {
            border = mkLiteral "2px 0 0";
            border-color = bg1;
            background-color = bg1;
          };

          "textbox" = {
            padding = mkLiteral "8px 24px";
          };

          "listview" = {
            lines = mkLiteral "10";
            columns = mkLiteral "1";

            fixed-height = mkLiteral "true";
            border = mkLiteral "1px 0 0";
            border-color = bg1;
          };

          "element" = {
            padding = mkLiteral "8px 16px";
            spacing = mkLiteral "16px";
            background-color = mkLiteral "transparent";
          };

          "element normal active" = {
            text-color = bg2;
          };

          "element selected normal, element selected active" = {
            background-color = bg2;
            text-color = fg1;
          };

          "element-icon" = {
            size = mkLiteral "1em";
          };

          "element-text" = {
            text-color = mkLiteral "inherit";
          };
        };
    };
}
