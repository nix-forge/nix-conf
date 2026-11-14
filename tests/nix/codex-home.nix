{
  pkgs,
  inputs,
  myLib,
}:
let
  inherit (pkgs) lib;
  backend =
    (pkgs.writeShellApplication {
      name = "codex";
      text = "exec ${lib.getExe pkgs.python3} ${../codex/fixtures/home-backend.py} \"$@\"";
    }).overrideAttrs
      { version = "999.0"; };
  fixturePkgs = pkgs.extend (_: _: { codex = backend; });
  homeFor =
    {
      prefer,
      enabled ? true,
      settings ? { },
    }:
    (inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = fixturePkgs;
      extraSpecialArgs = { inherit myLib; };
      modules = [
        ../../modules/home/dev/agentic-tui/codex-home.nix
        {
          options.programs.chatgpt.darwinBundle = lib.mkOption {
            type = lib.types.str;
            default = "Managed 'quoted' $app.app";
          };
        }
        {
          home.username = "codex-fixture";
          home.homeDirectory = "/fixture/home 'quoted' $literal";
          home.stateVersion = "26.05";
          home.preferXdgDirectories = prefer;
          xdg.configHome = "/fixture/custom config 'quoted' $literal";
          programs.codex.enable = enabled;
          programs.codex.settings = settings;
          programs.chatgpt.settings.shell_environment_policy = {
            "inherit" = "core";
            exclude = [
              "*TOKEN*"
              "*SECRET*"
            ];
            set.PRESERVED_SETTING = "fixture";
          };
        }
      ];
    }).config;
  variants = {
    xdg = homeFor { prefer = true; };
    legacy = homeFor { prefer = false; };
    gui = homeFor {
      prefer = true;
      enabled = false;
    };
  };
  conflicting =
    builtins.tryEval
      (homeFor {
        prefer = true;
        settings.model = "fixture";
      }).programs.chatgpt.codexHome;
  manifest = pkgs.writeText "codex-home-fixtures.json" (
    builtins.toJSON (
      lib.mapAttrs (_: home: {
        binary = if home.programs.codex.enable then lib.getExe home.programs.codex.package else "";
        raw = lib.getExe backend;
        home = home.programs.chatgpt.codexHome;
        desktopApp = null;
        policy = home.programs.chatgpt.settings.shell_environment_policy;
      }) variants
    )
  );
in
assert variants.xdg.programs.chatgpt.codexHome == "/fixture/custom config 'quoted' $literal/codex";
assert variants.legacy.programs.chatgpt.codexHome == "/fixture/home 'quoted' $literal/.codex";
assert variants.xdg.programs.codex.settings == { };
assert !variants.gui.programs.codex.enable;
assert !conflicting.success;
(import ../python-check.nix { inherit pkgs; }) {
  name = "codex-home-consistency";
  files = [ ../codex/test_home_wrapper.py ];
  testPaths = [ "tests/codex/test_home_wrapper.py" ];
  selection = "nix_integration";
  environment.CODEX_HOME_MANIFEST = manifest;
}
