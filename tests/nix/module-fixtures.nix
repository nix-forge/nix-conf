{
  inputs,
  pkgs,
  myLib,
}:
let
  inherit (pkgs) lib;
  # Inspect actual assertions without Home Manager's outer helper throwing
  # before negative fixtures can identify their owning compatibility message.
  homeFor =
    modules:
    let
      homePkgs = pkgs.extend (import ../../overlays { inherit inputs; });
      homeLib = import (inputs.home-manager + "/modules/lib/stdlib-extended.nix") lib;
    in
    (homeLib.evalModules {
      class = "homeManager";
      specialArgs = {
        inherit myLib inputs;
        inherit (inputs) self;
        system = pkgs.stdenv.hostPlatform.system;
        modulesPath = toString (inputs.home-manager + "/modules");
      };
      modules =
        modules
        ++ (import (inputs.home-manager + "/modules/modules.nix") {
          check = true;
          pkgs = homePkgs;
          lib = homeLib;
        })
        ++ [
          {
            home = {
              username = "tester";
              homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/tester" else "/home/tester";
              stateVersion = "26.05";
            };
            xdg.userDirs.enable = false;
          }
        ];
    }).config;
  systemFor =
    modules:
    (inputs.nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      specialArgs = { inherit inputs myLib; };
      modules = modules ++ [
        {
          system.stateVersion = "26.05";
          nixpkgs.config.allowUnfree = true;
          fileSystems."/" = {
            device = "/dev/disk/by-label/fixture-root";
            fsType = "ext4";
          };
          fileSystems."/boot" = {
            device = "/dev/disk/by-label/fixture-esp";
            fsType = "vfat";
          };
          boot.loader.grub.enable = false;
        }
      ];
    }).config;
  valid =
    config:
    lib.assertMsg (lib.all (entry: entry.assertion) config.assertions) (
      "Fixture compatibility assertions failed: "
      + lib.concatMapStringsSep "; " (entry: entry.message) (
        lib.filter (entry: !entry.assertion) config.assertions
      )
    );
  rejects =
    fragment: config:
    lib.any (entry: !entry.assertion && lib.hasInfix fragment entry.message) config.assertions;
in
{
  inherit
    homeFor
    systemFor
    valid
    rejects
    ;
}
