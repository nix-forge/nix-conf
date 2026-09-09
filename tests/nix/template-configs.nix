{
  pkgs,
  inputs,
  myLib,
}:
let
  inherit (pkgs) lib;
  font = "Test \"quoted\" font\\name";
  colors = lib.genAttrs (map (n: "base${n}") [
    "00"
    "01"
    "02"
    "03"
    "04"
    "05"
    "06"
    "07"
    "08"
    "09"
    "0A"
    "0B"
    "0C"
    "0D"
    "0E"
    "0F"
  ]) (_: "#123456");
  homeFor =
    modules:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = pkgs.extend (import ../../overlays { inherit inputs; });
      extraSpecialArgs = {
        inherit inputs myLib;
        system = pkgs.stdenv.hostPlatform.system;
        self.packages.${pkgs.stdenv.hostPlatform.system}.noctalia-personal = pkgs.noctalia;
      };
      modules = [
        inputs.stylix.homeModules.default
        (import ../../modules/shared/stylix/home.nix).homeManager
        ../../modules/home/desktop/bar.nix
        ../../modules/home/desktop/notifications.nix
        ../../modules/home/desktop/clipboard.nix
        ../../modules/home/desktop/idle.nix
        ../../modules/home/desktop/wallpaper.nix
        ../../modules/home/desktop/osd.nix
        ../../modules/home/desktop/launcher.nix
        ../../modules/home/desktop/walker.nix
        ../../modules/home/desktop/night-light.nix
        ../../modules/home/desktop/noctalia.nix
        {

          options.appearance.theme = lib.mkOption { type = lib.types.str; };
          config = {
            home = {
              username = "tester";
              homeDirectory = "/home/tester";
              stateVersion = "26.05";
            };
            stylix = {
              enable = true;
              autoEnable = false;
              base16Scheme = lib.mapAttrs (_: _: "123456") colors;
              targets = lib.genAttrs [ "noctalia" "hyprshell" "ironbar" "swaync" "swayosd" "walker" ] (_: {
                enable = true;
              });
              fonts.sansSerif.name = font;
              icons.dark = "test-icons";
            };
            appearance.theme = "carbon-neon-oled";
            xdg.userDirs.enable = true;
          };
        }
      ]
      ++ modules;
    };
  shell = homeFor [
    {
      desktop.noctalia.enable = true;
      wayland.windowManager.hyprland.enable = true;
      # The full desktop build validates with the personal Noctalia package.
      # This fixture independently parses the output and stresses font escaping.
      programs.noctalia.checkConfig = false;
    }
  ];
  desktop = homeFor [
    {
      desktop = {
        idle.enable = true;
        idle.onLockCommand = "printf 'locked'";
        clipboard = {
          enable = true;
          maxItems = 42;
          wipeOnLock = false;
        };
        notifications.enable = true;
        osd.enable = true;
        bar.enable = true;
        walker.enable = true;
        wallpaper = {
          enable = true;
          mode = "static";
          fitMode = "contain";
          outputs = {
            "DP-1" = "/home/tester/first wallpaper.png";
            "DP-2" = "/home/tester/second wallpaper.png";
          };
        };
      };
    }
  ];
  files = pkgs.linkFarm "generated-template-configs" {
    "noctalia.toml" = shell.config.xdg.configFile."noctalia/config.toml".source;
    "palette.json" = shell.config.xdg.configFile."noctalia/palettes/Stylix.json".source;
    "swaync.json" = desktop.config.xdg.configFile."swaync/config.json".source;
    "hypridle.conf" = desktop.config.xdg.configFile."hypr/hypridle.conf".source;
    "hyprpaper.conf" = desktop.config.xdg.configFile."hypr/hyprpaper.conf".source;
    "cliphist.conf" = desktop.config.xdg.configFile."cliphist/config".source;
    "ironbar.css" = desktop.config.xdg.configFile."ironbar/style.css".source;
    "swaync.css" = desktop.config.xdg.configFile."swaync/style.css".source;
    "swayosd.css" = desktop.config.xdg.configFile."swayosd/style.css".source;
    "swayosd-focused" = lib.getExe' (lib.findFirst (p: lib.getName p == "desktop-swayosd-focused")
      (throw "SwayOSD focused-output helper is missing")
      desktop.config.home.packages
    ) "desktop-swayosd-focused";
    "hyprshell.css" = shell.config.xdg.configFile."hyprshell/styles.css".source;
    "walker.toml" = desktop.config.xdg.configFile."walker/config.toml".source;
    "walker.css" = desktop.config.xdg.configFile."walker/themes/stylix/style.css".source;
  };
in
{
  template-configs =
    pkgs.runCommand "template-config-regressions"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        FILES = files;
        FONT = font;
      }
      ''
        python3 ${./check-template-configs.py}
        touch "$out"
      '';
}
