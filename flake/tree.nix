{ inputs, ... }:
let
  inherit (inputs) self;
  inherit (self) lib;
  inherit (lib.cust.files) importRec;
  tree =
    let
      configRoot = self; # the root of the flake
      excludes = [ "flake.nix" ]; # flake.nix is excluded to prevent infinite recursion
    in
    importRec configRoot excludes;
in
{
  flake = { inherit tree; };
}
