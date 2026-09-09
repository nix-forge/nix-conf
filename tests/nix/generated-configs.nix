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
  # Read the package's schema metadata without building the Darwin application.
  package = pkgs.callPackage ../../pkgs/pkgs/by-name/li/linearmouse/package.nix { };
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
    configurationSchemaVersion = "0.0.0";
  };
  mismatched = mouseFor { package = mismatchedPackage; };
  explicit = mouseFor {
    package = mismatchedPackage;
    settingsSchema = package.configurationSchema;
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
    ../../modules/home/karakeep.nix
    {
      services.actual = {
        enable = true;
        port = 41831;
        package = pkgs.writeShellScriptBin "actual-server" "exit 0";
      };
      services.karakeep = {
        enable = true;
        port = 41832;
      };
    }
  ];
  opener =
    name:
    lib.findFirst (p: lib.getName p == name) (throw "missing ${name}") openerHome.config.home.packages;
  browser = pkgs.writeShellScript "fixture-browser" ''
    printf '%s\n' "$@" >> "$OPEN_LOG"
  '';
in
{
  browser-openers = pkgs.runCommand "browser-openers" { nativeBuildInputs = [ pkgs.which ]; } ''
    export HOME="$TMPDIR/home" OPEN_LOG="$TMPDIR/urls" BROWSER=${browser}
    mkdir -p "$HOME"
    export DISPLAY=:99 XDG_CURRENT_DESKTOP=generic
    ${opener "actual-open"}/bin/actual-open
    ${opener "karakeep-extension-setup"}/bin/karakeep-extension-setup
    printf '%s\n' http://127.0.0.1:41831 http://localhost:41832 > expected
    cmp expected "$OPEN_LOG"
    touch "$out"
  '';
  linearmouse-config =
    assert !(builtins.tryEval mismatched.config.programs.linearmouse.settingsSchema).success;
    assert explicit.config.programs.linearmouse.settingsSchema == package.configurationSchema;
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
      ''
        python3 - ${osd.config.xdg.configFile."swayosd/config.toml".source} <<'PY'
        import os
        import sys
        import tomllib

        with open(sys.argv[1], "rb") as handle:
            config = tomllib.load(handle)
        assert config == {"server": {
            "style": os.environ["expectedStyle"],
            "min_brightness": 5,
            "show_percentage": True,
            "max_volume": 100,
            "keyboard_backlight": False,
            "top_margin": 0.85,
        }}, config
        PY
        touch "$out"
      '';
}
