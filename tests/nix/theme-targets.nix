{
  inputs,
  myLib,
  pkgs,
}:
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  linux = pkgs.stdenv.hostPlatform.isLinux;
  homeForWithHost =
    hostArgs: extra:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs myLib system;
        self.packages.${system} = {
          openai-codex-desktop = pkgs.emptyDirectory;
          noctalia-personal = pkgs.noctalia;
        };
      }
      // hostArgs;
      modules = [
        (import ../../modules/shared/fonts).homeManager
        (import ../../modules/shared/stylix).homeManager
        inputs.spicetify-nix.homeManagerModules.default
        ../../modules/home/desktop/bar.nix
        ../../modules/home/desktop/notifications.nix
        ../../modules/home/desktop/osd.nix
        ../../modules/home/desktop/walker.nix
        ../../modules/home/desktop/noctalia.nix
        ../../modules/home/desktop/night-light.nix
        ../../modules/home/desktop/idle.nix
        ../../modules/home/desktop/launcher.nix
        ../../modules/home/desktop/clipboard.nix
        {
          home = {
            username = "theme-check";
            homeDirectory = if linux then "/home/theme-check" else "/Users/theme-check";
            stateVersion = "26.05";
          };
          typography.designLibrary = "none";
          programs = {
            codex.enable = true;
            ghostty.enable = true;
            vscode.enable = true;
            spicetify.enable = true;
          };
          desktop = lib.mkIf linux {
            bar.enable = true;
            notifications.enable = true;
            osd.enable = true;
            walker.enable = true;
          };
        }
        extra
      ];
    };
  homeFor = homeForWithHost { };
  inherited =
    (homeForWithHost {
      osConfig = {
        stylix.enable = false;
        stylix.autoEnable = false;
        appearance.theme = "gruvbox-dark-medium";
      };
    } { }).config;
  shellFor =
    extra:
    (homeFor {
      imports = [ extra ];
      desktop.noctalia.enable = true;
      wayland.windowManager.hyprland.enable = true;
    }).config;
  shell = shellFor { };
  shellOff = shellFor { stylix.targets.noctalia.enable = false; };
  shellUpstream = shellFor { stylix.targets.noctalia.custom.enable = false; };
  chromiumFor =
    extra:
    (inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; };
      modules = [
        (import ../../modules/shared/stylix).nixos
        (import ../../modules/shared/chromium-policies.nix).nixos
        { appearance.theme = "catppuccin-mocha"; }
        extra
      ];
    }).config;
  chromium = chromiumFor { };
  chromiumOff = chromiumFor { stylix.targets.chromium-policies.enable = false; };
  enabled = (homeFor { }).config;
  duplicated =
    (homeFor {
      imports = [ (import ../../modules/shared/stylix/targets/codex-desktop/home.nix).homeManager ];
    }).config;
  disabled = (homeFor { stylix.enable = false; }).config;
  manual = (homeFor { stylix.autoEnable = false; }).config;
  optIn =
    (homeFor {
      stylix.autoEnable = false;
      stylix.targets.codex-desktop.enable = true;
    }).config;
  optOut =
    (homeFor {
      stylix.targets =
        lib.genAttrs
          [
            "codex-desktop"
            "ghostty"
            "vscode"
            "spicetify"
            "ironbar"
            "swaync"
            "swayosd"
            "walker"
          ]
          (_: {
            enable = false;
          });
    }).config;
  nativeOff =
    (homeFor {
      stylix = {
        targets = {
          vscode.custom.enable = false;
          spicetify.custom.enable = false;
          ghostty.custom.enable = false;
        };
      };
    }).config;
  absent =
    (homeFor {
      programs = {
        codex.enable = lib.mkForce false;
        vscode.enable = lib.mkForce false;
        spicetify.enable = lib.mkForce false;
        ghostty.enable = lib.mkForce false;
      };
      desktop.bar.enable = lib.mkForce false;
      desktop.walker.enable = lib.mkForce false;
    }).config;
  noCustom =
    c:
    !(c.home.activation ? configureCodexDesktopAppearance)
    && !(c.programs.ghostty.settings ? selection-background)
    && !(c.xdg.configFile ? "ironbar/style.css")
    && !(c.xdg.configFile ? "swaync/style.css")
    && !(c.xdg.configFile ? "swayosd/style.css")
    && !(c.xdg.configFile ? "walker/themes/stylix/style.css");
in
assert !inherited.stylix.enable && !inherited.stylix.autoEnable;
assert
  !linux
  || (
    shell.programs.noctalia.customPalettes ? Stylix
    && !(shellOff.programs.noctalia.customPalettes ? Stylix)
    && shellOff.programs.noctalia.enable
    && !shellOff.programs.noctalia.settings.theme.templates.enable_community_templates
    && shellUpstream.programs.noctalia.settings.theme.custom_palette == "stylix"
    && !(shellUpstream.programs.noctalia.customPalettes ? Stylix)
  );
assert
  !linux
  || (
    chromium.programs.chromiumPolicies.heliumExtensions ? catppuccinMocha
    && !(chromiumOff.programs.chromiumPolicies.heliumExtensions ? catppuccinMocha)
    && chromiumOff.programs.chromiumPolicies.heliumExtensions ? bitwarden
  );
assert enabled.home.activation ? configureCodexDesktopAppearance;
assert !linux || !(disabled.desktop.walker.settings ? theme);
assert
  duplicated.home.activation.configureCodexDesktopAppearance.data
  == enabled.home.activation.configureCodexDesktopAppearance.data;
assert noCustom disabled;
assert noCustom manual;
assert noCustom optOut;
assert optIn.home.activation ? configureCodexDesktopAppearance;
assert !(optIn.programs.ghostty.settings ? selection-background);
assert !(nativeOff.programs.ghostty.settings ? selection-background);
assert !(absent.home.activation ? configureCodexDesktopAppearance);
assert !(absent.xdg.configFile ? "ironbar/style.css");
assert !(absent.xdg.configFile ? "walker/themes/stylix/style.css");
assert (enabled.xdg.configFile ? "ironbar/style.css") == linux;
assert (enabled.xdg.configFile ? "walker/themes/stylix/style.css") == linux;
assert
  disabled.programs.codex.enable
  && disabled.programs.vscode.enable
  && disabled.programs.spicetify.enable;
assert
  !linux || (disabled.systemd.user.services ? ironbar && disabled.systemd.user.services ? swaync);
pkgs.runCommand "theme-target-contracts" { } "touch $out"
