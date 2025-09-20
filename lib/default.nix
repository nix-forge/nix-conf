{ inputs, ... }:
let
  inherit (inputs.nixpkgs) lib;

  extendedLib = lib // {
    cust = {
      nixos = import ./nixos;
      darwin = import ./darwin;
      builders = import ./builders.nix { inherit lib; };
      scanPaths = import ./scanPaths.nix { inherit lib; };
      files = import ./files { inherit lib; };
      applyAutoArgs = import ./applyAutoArgs.nix { inherit lib; };
      withTreeModules = import ./withTreeModules.nix;
    };
  };

in
{
  perSystem = {
    imports = [ { _module.args.lib = extendedLib; } ];
  };

  flake = {
    lib = extendedLib;
  };
}
