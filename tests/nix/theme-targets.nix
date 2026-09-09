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
  walkerOverride =
    (homeFor {
      desktop.walker.settings = {
        theme = "chosen-theme";
        providers.max_results = 7;
      };
    }).config;
  walkerDefaultsSurvive =
    c:
    (c.desktop.walker.settings.force_keyboard_focus or false)
    && (c.desktop.walker.settings.shell.anchor_top or false)
    && (c.desktop.walker.settings.keybinds.close or [ ]) == [ "Escape" ]
    &&
      (c.desktop.walker.settings.providers.default or [ ]) == [
        "desktopapplications"
        "calc"
      ]
    && lib.any (entry: entry.prefix == "/" && entry.provider == "files") (
      c.desktop.walker.settings.providers.prefixes or [ ]
    );
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
  profiles = (homeFor { stylix.targets.vscode.profileNames = [ "work" ]; }).config;
  noCustom =
    c:
    !(c.home.activation ? configureCodexDesktopAppearance)
    && !(c.programs.ghostty.settings ? selection-background)
    && !(c.xdg.configFile ? "ironbar/style.css")
    && !(c.xdg.configFile ? "swaync/style.css")
    && !(c.xdg.configFile ? "swayosd/style.css")
    && !(c.xdg.configFile ? "walker/themes/stylix/style.css");
  schemes = {
    carbon-neon = "Carbon Neon";
    carbon-neon-oled = "Carbon Neon OLED";
    catppuccin-mocha = "Catppuccin Mocha";
    gruvbox-dark-medium = "Gruvbox Dark (Medium)";
  };
  schemeChecks = lib.mapAttrsToList (
    theme: expected:
    let
      c = (homeFor { appearance.theme = theme; }).config;
    in
    c.programs.vscode.profiles.default.userSettings."workbench.colorTheme" == expected
    && c.programs.ghostty.settings.selection-background == [ c.appearance.palette.accent ]
    &&
      c.programs.spicetify.colorScheme == {
        carbon-neon = "custom";
        carbon-neon-oled = "custom";
        catppuccin-mocha = "mocha";
        gruvbox-dark-medium = "Gruvbox";
      }
      .${theme}
  ) schemes;
in
assert !inherited.stylix.enable && !inherited.stylix.autoEnable;
assert inherited.appearance.theme == "gruvbox-dark-medium";
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
    &&
      chromium.programs.chromiumPolicies.heliumExtensions.bitwarden == "nngceckbapebfimnlniiiahkandclblb"
    && !(chromiumOff.programs.chromiumPolicies.heliumExtensions ? catppuccinMocha)
    && chromiumOff.programs.chromiumPolicies.heliumExtensions ? bitwarden
    && chromium.programs.chromiumPolicies.heliumExtensions ? sponsorBlock
    && chromium.programs.chromiumPolicies.heliumExtensions ? karakeep
    && chromium.programs.chromiumPolicies.heliumExtensions ? refinedGitHub
    &&
      lib.length chromium.programs.chromiumPolicies.targets.google-chrome.policies.ExtensionInstallForcelist
      == 2
    &&
      lib.length chromiumOff.programs.chromiumPolicies.targets.google-chrome.policies.ExtensionInstallForcelist
      == 1
  );
assert enabled.home.activation ? configureCodexDesktopAppearance;
assert
  !linux
  || lib.all walkerDefaultsSurvive [
    enabled
    disabled
    optOut
    walkerOverride
  ];
assert !linux || enabled.desktop.walker.settings.theme == "stylix";
assert !linux || !(disabled.desktop.walker.settings ? theme);
assert !linux || walkerOverride.desktop.walker.settings.theme == "chosen-theme";
assert !linux || walkerOverride.desktop.walker.settings.providers.max_results == 7;
assert
  duplicated.home.activation.configureCodexDesktopAppearance.data
  == enabled.home.activation.configureCodexDesktopAppearance.data;
assert noCustom disabled;
assert noCustom manual;
assert noCustom optOut;
assert optIn.home.activation ? configureCodexDesktopAppearance;
assert !(optIn.programs.ghostty.settings ? selection-background);
assert nativeOff.programs.vscode.profiles.default.userSettings."workbench.colorTheme" == "Stylix";
assert nativeOff.programs.spicetify.colorScheme == "base";
assert !(nativeOff.programs.ghostty.settings ? selection-background);
assert !(absent.home.activation ? configureCodexDesktopAppearance);
assert !(absent.xdg.configFile ? "ironbar/style.css");
assert !(absent.xdg.configFile ? "walker/themes/stylix/style.css");
assert profiles.programs.vscode.profiles.work.userSettings."workbench.colorTheme" == "Carbon Neon";
assert !((profiles.programs.vscode.profiles.default.userSettings or { }) ? "workbench.colorTheme");
assert lib.all (x: x) schemeChecks;
assert (enabled.xdg.configFile ? "ironbar/style.css") == linux;
assert (enabled.xdg.configFile ? "walker/themes/stylix/style.css") == linux;
assert
  disabled.programs.codex.enable
  && disabled.programs.vscode.enable
  && disabled.programs.spicetify.enable;
assert
  !linux || (disabled.systemd.user.services ? ironbar && disabled.systemd.user.services ? swaync);
pkgs.runCommand "theme-target-contracts" { } "touch $out"
