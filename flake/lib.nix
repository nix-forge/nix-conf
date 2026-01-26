{ inputs, ... }:
let
  extendedLib = import ../lib { inherit (inputs.nixpkgs) lib; };
in
{
  perSystem = {
    _module.args.lib = extendedLib;
    flake.lib = extendedLib;
  };
}
