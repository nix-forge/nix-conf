{ inputs }:
let
  fixes = import ./temporary {
    inherit inputs;
    inherit (inputs.nixpkgs) lib;
  };
in
inputs
// {
  determinate = inputs.determinate // {
    nixosModules = inputs.determinate.nixosModules // {
      default = fixes.apply "determinate-libgit2-module" inputs.determinate;
    };
  };
}
