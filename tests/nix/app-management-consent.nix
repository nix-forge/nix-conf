{ pkgs, inputs }:
let
  inherit (pkgs) lib;
  fixes = import ../../overlays/temporary { inherit inputs lib; };
  root = fixes.apply "darwin-app-management-consent" inputs.nix-darwin;
  protected = fixes.apply "home-manager-protected-apps" inputs.home-manager;
  home = fixes.apply "home-manager-app-management-consent" {
    upstream = inputs.home-manager;
    replacement = protected;
  };
  hmLib = lib // {
    hm.dag = import (inputs.home-manager + "/modules/lib/dag.nix") { lib = hmLib; };
  };
  rootCheck =
    path:
    (import path {
      inherit lib;
      config = { };
      pkgs = { };
    }).config.system.checks.text.content;
  homeCheck =
    path:
    (import path {
      lib = hmLib;
      pkgs = { };
      config.targets.darwin.copyApps = {
        enable = true;
        enableChecks = true;
        directory = "apps";
      };
    }).config.content.home.activation.checkAppManagementPermission.content;
  rawHome = homeCheck (inputs.home-manager + "/modules/targets/darwin/copyapps.nix");
  fixedHome = homeCheck (builtins.head home.imports);
  originalHomeSource = builtins.readFile (
    inputs.home-manager + "/modules/targets/darwin/copyapps.nix"
  );
  fixedHomeSource = builtins.readFile (builtins.head home.imports);
  fragments = pkgs.writeText "app-management-consent-fragments.json" (
    builtins.toJSON {
      baseline = {
        root = rootCheck (inputs.nix-darwin + "/modules/system/applications.nix");
        home = rawHome.data;
      };
      fixed = {
        root = rootCheck (builtins.head root.imports);
        home = fixedHome.data;
      };
    }
  );
in
assert rawHome.before == fixedHome.before;
assert rawHome.after == fixedHome.after;
assert lib.hasInfix "if [[ ! -L 'apps' ]] && ! ensureAppManagement; then" fixedHome.data;
assert lib.hasInfix "--checksum" fixedHomeSource;
assert lib.hasInfix "--copy-unsafe-links" fixedHomeSource;
assert lib.hasInfix "--delete" fixedHomeSource;
assert lib.hasInfix "config.macos.applications.protectedBundles" fixedHomeSource;
assert lib.hasInfix "enableChecks" originalHomeSource;
pkgs.runCommand "darwin-app-management-consent"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.python3Packages.pytest
    ];
    APP_MANAGEMENT_FRAGMENTS = fragments;
    APP_MANAGEMENT_BASH = lib.getExe pkgs.bash;
  }
  ''
    cp ${../macos/test_app_management_consent.py} ./test_app_management_consent.py
    pytest --rootdir="$PWD" --confcutdir="$PWD" \
      --override-ini addopts= -q ./test_app_management_consent.py
    touch "$out"
  ''
