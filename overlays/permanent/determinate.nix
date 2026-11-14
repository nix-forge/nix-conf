{ inputs }:
_final: prev:
let
  inherit (prev.stdenv.hostPlatform) system;
  nixSource = inputs.determinate.inputs.nix;
  upstream = nixSource.packages.${system}.default;
  temporary = import ../temporary {
    inherit inputs;
    pkgs = prev;
  };
  scoped =
    let
      owningPkgs = import nixSource.inputs.nixpkgs {
        localSystem = { inherit system; };
        overlays = [ nixSource.overlays.internal ];
      };
      raw = owningPkgs.nixComponents2.nix-everything;
      owningTemporary = import ../temporary {
        inherit inputs;
        pkgs = owningPkgs;
      };
      libgit2 = owningTemporary.apply "determinate-libgit2-trailing-slash" owningPkgs.nixDependencies2.libgit2;
      scope = owningPkgs.nixComponents2.overrideScope (_final: _prev: { inherit libgit2; });
    in
    assert raw.drvPath == upstream.drvPath;
    scope.nix-everything;
in
{
  nix =
    if prev.stdenv.hostPlatform.isDarwin then
      temporary.apply "determinate-darwin-tests" scoped
    else
      scoped;
}
