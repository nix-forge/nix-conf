{ inputs, ... }:
let
  extendedLib = import ../lib { inherit (inputs.nixpkgs) lib; };
in
{
  flake.lib = extendedLib;
  perSystem._module.args.lib = extendedLib;
}
