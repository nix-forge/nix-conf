{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  inherit ((import ../../modules/shared/stylix/schemes.nix { inherit inputs; })) schemes;
  lightScheme = inputs.stylix.inputs.tinted-schemes + "/base16/solarized-light.yaml";
  base16 = inputs.stylix.inputs.base16.lib { inherit pkgs lib; };
  withoutMetadata =
    scheme:
    lib.filterAttrs (name: _: builtins.match "base[0-9A-F]{2}" name != null) (
      base16.mkSchemeAttrs scheme
    );
  customTheme = pkgs.runCommand "gtk-alternate-theme-fixture" { } (
    (import ../../lib/templates/text.nix) ./scripts/gtk-alternate-theme-fixture.sh {
      pkgs_adw_gtk3 = pkgs.adw-gtk3;
    }
  );
  homeFor =
    extra:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit inputs; };
      modules = [
        (import ../../modules/shared/stylix/targets/gtk/home.nix).homeManager
        {
          home = {
            username = "gtk-check";
            homeDirectory = "/home/gtk-check";
            stateVersion = "26.05";
          };
          appearance.theme = "carbon-neon-oled";
          stylix = {
            enable = true;
            autoEnable = false;
            targets.gtk.enable = true;
            targets.gtk.flatpakSupport.enable = true;
          };
        }
        extra
      ];
    }).config;
  cases =
    lib.mapAttrs (_: scheme: {
      stylix.base16Scheme = lib.mkForce scheme;
      stylix.polarity = "dark";
    }) schemes
    // {
      light = {
        stylix.base16Scheme = lib.mkForce lightScheme;
        stylix.polarity = "light";
      };
      either-dark = {
        stylix.polarity = "either";
      };
      either-light = {
        stylix.base16Scheme = lib.mkForce lightScheme;
        stylix.polarity = "either";
      };
      custom = {
        stylix.polarity = "dark";
        gtk.theme = lib.mkForce {
          name = "alternate-theme";
          package = customTheme;
        };
      };
      inferred-dark = {
        stylix.base16Scheme = lib.mkForce (withoutMetadata schemes.carbon-neon-oled);
        stylix.polarity = "either";
      };
      inferred-light = {
        stylix.base16Scheme = lib.mkForce (withoutMetadata lightScheme);
        stylix.polarity = "either";
      };
      custom-light = {
        stylix.base16Scheme = lib.mkForce lightScheme;
        stylix.polarity = "light";
        gtk.theme = lib.mkForce {
          name = "alternate-theme";
          package = customTheme;
        };
      };
    };
  disabled = homeFor { stylix.enable = lib.mkForce false; };
  targetOff = homeFor { stylix.targets.gtk.enable = lib.mkForce false; };
  colorsOff = homeFor { stylix.targets.gtk.colors.enable = false; };
  userPreference = homeFor {
    stylix.polarity = "dark";
    gtk.gtk3.extraConfig.gtk-application-prefer-dark-theme = false;
  };
  nixFlatpak = homeFor {
    options.services.flatpak.overrides = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };
    config.stylix.polarity = "light";
  };
  fixtures = lib.mapAttrs (name: extra: {
    config = homeFor extra;
    expectedDark =
      !(builtins.elem name [
        "light"
        "either-light"
        "inferred-light"
        "custom-light"
      ]);
  }) cases;
  python = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
  probe = ../gtk/check_dialog_contrast.py;
in
assert !(disabled.gtk.gtk3.extraConfig ? gtk-application-prefer-dark-theme);
assert !(targetOff.gtk.gtk3.extraConfig ? gtk-application-prefer-dark-theme);
assert !(colorsOff.gtk.gtk3.extraConfig ? gtk-application-prefer-dark-theme);
assert !userPreference.gtk.gtk3.extraConfig.gtk-application-prefer-dark-theme;
assert lib.hasInfix "GTK_THEME=${userPreference.gtk.theme.name}:light"
  userPreference.xdg.dataFile."flatpak/overrides/global".text;
assert
  nixFlatpak.services.flatpak.overrides.global.Environment.GTK_THEME
  == "${nixFlatpak.gtk.theme.name}:light";
assert builtins.all (
  fixture:
  !(fixture.config.gtk.gtk4.extraConfig ? gtk-application-prefer-dark-theme)
  && !(fixture.config.home.sessionVariables ? GTK_THEME)
) (builtins.attrValues fixtures);
pkgs.runCommand "gtk-polarity-dialog-contrast"
  {
    nativeBuildInputs = [
      pkgs.xvfb-run
      pkgs.gobject-introspection
    ];
    buildInputs = [ pkgs.gtk3 ];
  }
  (
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name:
        { config, expectedDark }:
        let
          themeName = config.gtk.theme.name;
          flattened = config.home.file.".themes/${themeName}".source;
          settings = config.xdg.configFile."gtk-3.0/settings.ini".source;
          css = config.xdg.configFile."gtk-3.0/gtk.css".source;
          overrides = config.xdg.dataFile."flatpak/overrides/global".source;
        in
        (import ../../lib/templates/text.nix) ./scripts/check-gtk-dialog-contrast.sh {
          inherit name;
          config_gtk_theme_package = config.gtk.theme.package;
          inherit settings;
          inherit css;
          pkgs_gnugrep = pkgs.gnugrep;
          inherit flattened;
          lib_boolToString_expectedDark = lib.boolToString expectedDark;
          inherit python;
          inherit probe;
          inherit themeName;
          pkgs_gnused = pkgs.gnused;
          inherit overrides;
        }
      ) fixtures
    )
    + (builtins.readFile ./scripts/complete-gtk-dialog-check.sh)
  )
