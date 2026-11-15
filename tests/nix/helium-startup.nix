{
  pkgs,
  inputs,
  myLib,
}:
let
  inherit (pkgs) lib;
  profile = "/tmp/helium-startup-fixture/Default";
  fakePackage = pkgs.runCommand "helium-startup-fixture" { } "mkdir -p $out";
  home = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs myLib;
      system = pkgs.stdenv.hostPlatform.system;
      osConfig = null;
    };
    modules = [
      ../../modules/home/browsers/helium
      {
        config = {
          home = {
            username = "tester";
            homeDirectory = "/tmp/helium-startup-fixture";
            stateVersion = "26.05";
          };
          programs.browserSuite.chromium.heliumExtensions = lib.mkForce { };
          programs.helium = {
            enable = true;
            package = fakePackage;
            flags = lib.mkForce [ ];
            profileDirectory = profile;
            preferenceDefaults = lib.mkForce { helium.browser.layout = 7; };
            preferenceDefaultsRemovals = [ [ "obsolete" ] ];
          };
        };
      }
    ];
  };
  package = lib.findFirst (
    p: p.name == fakePackage.name
  ) (throw "missing Helium package") home.config.home.packages;
in
pkgs.runCommand "helium-startup"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.makeWrapper
      pkgs.bash
    ];
    startup = pkgs.writeText "helium-post-install.sh" package.postInstall;
    fixture = ./scripts/check_helium_startup.py;
    fakeBrowser = pkgs.replaceVars ./scripts/helium-fake-browser.sh.in { bash = lib.getExe pkgs.bash; };
    inherit profile;
    BASH_PROGRAM = lib.getExe pkgs.bash;
    BUILD_SETUP = "${pkgs.stdenv}/setup";
  }
  ''
    python3 "$fixture" "$startup" "$fakeBrowser" "$profile"
    mkdir -p "$out"
  ''
