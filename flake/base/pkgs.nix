{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };
    in
    {
      _module.args.pkgs = pkgs;
      packages = import ../../pkgs { inherit pkgs; };
    };
}
