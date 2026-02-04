{ inputs, ... }:
let
  extendedLib = import ../../lib { inherit (inputs.nixpkgs) lib; };
in
{
  flake.lib = extendedLib;
  _module.args.myLib = extendedLib;
}
