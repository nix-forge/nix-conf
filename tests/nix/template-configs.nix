{
  pkgs,
  inputs,
  myLib,
}:
let
  inherit (pkgs) lib;
  homePkgs = pkgs.extend (import ../../overlays { inherit inputs; });
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
  testHyprland = lib.extendDerivation true { override = _: testHyprland; } (
    pkgs.runCommand "test-hyprland-clients" { } (
      builtins.readFile ./scripts/create-hyprland-client-stubs.sh
    )
  );
  homeForWithOsConfig =
    osConfig: modules:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = homePkgs;
      extraSpecialArgs = {
        inherit inputs myLib;
        inherit osConfig;
        system = pkgs.stdenv.hostPlatform.system;
        self.packages.${pkgs.stdenv.hostPlatform.system}.noctalia-personal = pkgs.noctalia;
      };
      modules = [
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

          config = {
            home = {
              username = "tester";
              homeDirectory = "/home/tester";
              stateVersion = "26.05";
            };
            stylix = {
              enable = true;
              autoEnable = false;
              # A readable accent should survive contrast preparation unchanged.
              base16Scheme = lib.mkForce (lib.mapAttrs (_: _: "123456") colors // { base0D = "abcdef"; });
              targets = lib.genAttrs [ "noctalia" "hyprshell" "ironbar" "swaync" "swayosd" "walker" ] (_: {
                enable = true;
              });
              fonts.sansSerif.name = lib.mkForce font;
              icons.dark = lib.mkForce "test-icons";
            };
            appearance.theme = "carbon-neon-oled";
            xdg.userDirs.enable = true;
            wayland.windowManager.hyprland = {
              enable = true;
              package = lib.mkDefault testHyprland;
            };
          };
        }
      ]
      ++ modules;
    };
  homeFor = homeForWithOsConfig null;
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
  backgroundDesktop = homeFor [
    {
      desktop.idle = {
        enable = true;
        backgroundAppClasses = [ "chatgpt" ];
      };
      wayland.windowManager.hyprland = {
        enable = true;
        package = testHyprland;
      };
    }
  ];
  noSuspendDesktop =
    homeForWithOsConfig
      {
        services.hypridle.enable = false;
        systemd.sleep.settings.Sleep.AllowSuspend = "no";
      }
      [
        {
          desktop.idle.enable = true;
          desktop.noctalia.enable = true;
          wayland.windowManager.hyprland.enable = true;
          programs.noctalia.checkConfig = false;
        }
      ];
  missingCompositor = homeFor [
    {
      desktop.idle.enable = true;
      wayland.windowManager.hyprland.enable = lib.mkForce false;
    }
  ];
  missingLocker = homeFor [
    {
      desktop.idle.enable = true;
      programs.hyprlock.enable = false;
    }
  ];
  externalCompositor = homeFor [
    {
      desktop.idle.enable = true;
      wayland.windowManager.hyprland.package = lib.mkForce null;
    }
  ];
  systemCompositor =
    homeForWithOsConfig
      {
        programs.hyprland = {
          enable = true;
          package = testHyprland;
        };
      }
      [
        {
          desktop.idle.enable = true;
          wayland.windowManager.hyprland.package = lib.mkForce null;
        }
      ];
  files = pkgs.linkFarm "generated-template-configs" {
    "noctalia.toml" = shell.config.xdg.configFile."noctalia/config.toml".source;
    "palette.json" = shell.config.xdg.configFile."noctalia/palettes/Stylix.json".source;
    "swaync.json" = desktop.config.xdg.configFile."swaync/config.json".source;
    "hypridle.conf" = desktop.config.xdg.configFile."hypr/hypridle.conf".source;
    "hypridle-background.conf" = backgroundDesktop.config.xdg.configFile."hypr/hypridle.conf".source;
    "hypridle-no-suspend.conf" = noSuspendDesktop.config.xdg.configFile."hypr/hypridle.conf".source;
    "noctalia-no-suspend.toml" = noSuspendDesktop.config.xdg.configFile."noctalia/config.toml".source;
    "hyprpaper.conf" = desktop.config.xdg.configFile."hypr/hyprpaper.conf".source;
    "cliphist.conf" = desktop.config.xdg.configFile."cliphist/config".source;
    "ironbar.css" = desktop.config.xdg.configFile."ironbar/style.css".source;
    "swaync.css" = desktop.config.xdg.configFile."swaync/style.css".source;
    "swayosd.css" = desktop.config.xdg.configFile."swayosd/style.css".source;
    "hyprshell.css" = shell.config.xdg.configFile."hyprshell/styles.css".source;
    "walker.toml" = desktop.config.xdg.configFile."walker/config.toml".source;
    "walker.css" = desktop.config.xdg.configFile."walker/themes/stylix/style.css".source;
  };
in
{
  walker-config = desktop.config.xdg.configFile."walker/config.toml".source;
  template-configs =
    assert lib.all (entry: entry.assertion) desktop.config.assertions;
    assert !(builtins.tryEval missingCompositor.activationPackage.drvPath).success;
    assert !(builtins.tryEval missingLocker.activationPackage.drvPath).success;
    assert lib.hasInfix
      (builtins.unsafeDiscardStringContext "${lib.getExe' homePkgs.hyprland "hyprctl"} dispatch")
      externalCompositor.config.xdg.configFile."hypr/hypridle.conf".text;
    assert lib.hasInfix
      (builtins.unsafeDiscardStringContext "${lib.getExe' testHyprland "hyprctl"} dispatch")
      systemCompositor.config.xdg.configFile."hypr/hypridle.conf".text;
    pkgs.runCommand "template-config-regressions"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        FILES = files;
        FONT = font;
        HYPRCTL = lib.getExe' testHyprland "hyprctl";
        LOGINCTL = lib.getExe' pkgs.systemd "loginctl";
        SYSTEMCTL = lib.getExe' pkgs.systemd "systemctl";
      }
      (
        (import ../../lib/templates/text.nix) ./scripts/template-config-regressions.sh {
          check_template_configs_py = ./check_template_configs.py;
        }
      );
}
