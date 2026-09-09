{
  homeManager =
    {
      config,
      lib,
      pkgs,
      self,
      system,
      options,
      ...
    }:
    let
      cfg = config.desktop.noctalia;
      target = config.stylix.targets.noctalia;
      colors = config.lib.stylix.colors.withHashtag;
      noctalia = lib.getExe config.programs.noctalia.package;
      darkAppIcons = self.packages.${system}.noctalia-dark-app-icons;
      syncAppIcons = pkgs.writeShellApplication {
        name = "noctalia-sync-app-icons";
        runtimeInputs = [ pkgs.glib ];
        text = ''
          mode="''${NOCTALIA_THEME_MODE:-}"
          if [[ -z "$mode" ]]; then
            mode="$(${noctalia} msg theme-mode-get)"
          fi
          case "$mode" in
            dark) theme=${lib.escapeShellArg darkAppIcons.iconThemeName} ;;
            light) theme=${lib.escapeShellArg config.stylix.icons.light} ;;
            *) echo "Unknown Noctalia theme mode: $mode" >&2; exit 1 ;;
          esac
          gsettings set org.gnome.desktop.interface icon-theme "$theme"
        '';
      };
    in
    {
      key = "nix-conf/stylix/noctalia/homeManager";
      _file = __curPos.file;
      options.stylix.targets.noctalia.custom.enable = lib.mkEnableOption "the desktop Noctalia theme" // {
        default = true;
      };
      config = lib.optionalAttrs (options ? desktop.noctalia) (
        lib.mkIf (config.stylix.enable && target.enable && target.custom.enable && cfg.enable) {
          # This target owns the full native palette and visual baseline. Leave
          # upstream available through custom.enable = false, without replacing code.
          stylix.targets.noctalia = {
            colors.enable = lib.mkDefault false;
            fonts.enable = lib.mkDefault false;
            opacity.enable = lib.mkDefault false;
            polarity.enable = lib.mkDefault false;
            image.enable = lib.mkDefault false;
          };
          home.packages = lib.optional cfg.darkAppIcons.enable darkAppIcons;
          xdg.dataFile = lib.optionalAttrs cfg.darkAppIcons.enable {
            "icons/${darkAppIcons.iconThemeName}".source =
              "${darkAppIcons}/share/icons/${darkAppIcons.iconThemeName}";
          };
          programs.noctalia = {
            customPalettes.Stylix = (import ./palette.nix).render { inherit colors; };
            settings = lib.mkMerge [
              ((import ./settings.nix).render {
                font = config.stylix.fonts.sansSerif.name;
                paletteName = "Stylix";
                pureBlackDark = config.appearance.theme == "carbon-neon-oled";
              })
              {
                widget = lib.optionalAttrs cfg.symbolicBarIcons.enable {
                  active_window.symbolic_icons = true;
                  taskbar.symbolic_icons = true;
                  tray.icon_overrides = cfg.symbolicBarIcons.trayOverrides;
                };
                hooks = lib.optionalAttrs cfg.darkAppIcons.enable {
                  started = [ (lib.getExe syncAppIcons) ];
                  theme_mode_changed = [ (lib.getExe syncAppIcons) ];
                };

                dock = lib.mkIf cfg.dock.enable {
                  icon_size = 42;
                  # Keep artwork at full opacity and size regardless of window focus.
                  # Running dots and hover magnification provide the state feedback.
                  active_opacity = 1.0;
                  inactive_opacity = 1.0;
                  active_scale = 1.0;
                  inactive_scale = 1.0;
                  main_axis_padding = 12;
                  cross_axis_padding = 6;
                  item_spacing = 4;
                  background_opacity = 0.96;
                  radius = 14;
                  margin_edge = 10;
                  shadow = false;
                };
              }
            ];
          };
        }
      );
    };
}
