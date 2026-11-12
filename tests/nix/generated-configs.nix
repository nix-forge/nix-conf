{
  pkgs,
  inputs,
  myLib,
}:
let
  inherit (pkgs) lib;
  homeFor =
    modules:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit myLib; };
      modules = modules ++ [
        {
          home.username = "tester";
          home.homeDirectory = "/home/tester";
          home.stateVersion = "26.05";
        }
      ];
    };
  # Check generated settings without building the Darwin application on Linux.
  schemaSource = import ../../modules/home/linearmouse-assets/schema-source.nix;
  schema = pkgs.fetchurl schemaSource.src;
  package = (import inputs.nixpkgs-apps { system = pkgs.stdenv.hostPlatform.system; }).linearmouse;
  mouseFor =
    settings:
    homeFor [
      ../../modules/home/linearmouse.nix
      {
        # This fixture builds only JSON on Linux, never the app or activation.
        assertions = lib.mkForce [ ];
        programs.linearmouse = {
          inherit package;
          enable = true;
        }
        // settings;
      }
    ];
  mouse = mouseFor {
    settings.schemes = [
      {
        "if".device.category = "mouse";
        pointer = {
          acceleration = "unset";
          speed = "unset";
          disableAcceleration = false;
        };
        scrolling.reverse.vertical = true;
      }
    ];
  };
  invalid = mouseFor { settings.schemes = "not an array"; };
  mismatchedPackage = package // {
    version = "0.0.0";
  };
  mismatched = mouseFor { package = mismatchedPackage; };
  explicit = mouseFor {
    package = mismatchedPackage;
    settingsSchema = schema;
  };
  external = mouseFor {
    settingsSchema = pkgs.writeText "external-schema.json" (
      builtins.toJSON { "$ref" = "https://example.invalid/configuration.json"; }
    );
  };
  configHome = "/home/tester/a \"quoted\" path\\with-backslash";
  osd = homeFor [
    ../../modules/home/desktop/osd.nix
    {
      desktop.osd.enable = true;
      xdg.configHome = configHome;
      xdg.configFile."swayosd/style.css".text = "window { color: white; }";
    }
  ];
  openerHome = homeFor [
    ../../modules/home/actual.nix
    {
      services.actual = {
        enable = true;
        port = 41831;
        package = pkgs.writeShellScriptBin "actual-server" "exit 0";
      };
    }
  ];
  opener =
    name:
    lib.findFirst (p: lib.getName p == name) (throw "missing ${name}") openerHome.config.home.packages;
  browser = pkgs.writeShellScript "fixture-browser" (builtins.readFile ./scripts/fixture-browser.sh);
in
{
  usbguard-policy = pkgs.runCommand "usbguard-policy" { nativeBuildInputs = [ pkgs.usbguard ]; } ''
    usbguard-rule-parser -f ${../../hosts/nixos/desktop/local/security/usbguard.rules} > /dev/null
    touch "$out"
  '';
  browser-openers = pkgs.runCommand "browser-openers" { nativeBuildInputs = [ pkgs.which ]; } (
    (import ../../lib/templates/text.nix) ./scripts/browser-openers.sh {
      inherit browser;
      opener_actual_open = opener "actual-open";
    }
  );
  linearmouse-config =
    assert !(builtins.tryEval mismatched.config.programs.linearmouse.settingsSchema).success;
    assert explicit.config.programs.linearmouse.settingsSchema == schema;
    mouse.config.programs.linearmouse.settingsFile;
  linearmouse-invalid-config = pkgs.testers.testBuildFailure' {
    drv = invalid.config.programs.linearmouse.settingsFile;
    expectedBuilderLogEntries = [ "'not an array' is not of type 'array'" ];
  };
  linearmouse-external-schema = pkgs.testers.testBuildFailure' {
    drv = external.config.programs.linearmouse.settingsFile;
    expectedBuilderLogEntries = [ "LinearMouse settingsSchema must be self-contained" ];
  };
  swayosd-config =
    pkgs.runCommand "swayosd-config-escaping"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        expectedStyle = "${configHome}/swayosd/style.css";
      }
      (
        (import ../../lib/templates/text.nix) ./scripts/swayosd-config-escaping.sh {
          scripts_generated_configs_check_py = ./scripts/generated_configs_check.py;
          osd_config_xdg_configFile_swayosd_config_toml_source =
            osd.config.xdg.configFile."swayosd/config.toml".source;
        }
      );
}
