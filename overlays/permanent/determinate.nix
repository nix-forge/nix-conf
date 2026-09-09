{ inputs }:
_final: prev:
let
  inherit (prev.stdenv.hostPlatform) system;
  upstream = inputs.determinate.inputs.nix.packages.${system}.default;
in
{
  nix =
    if prev.stdenv.hostPlatform.isDarwin then
      (import ../temporary {
        inherit inputs;
        pkgs = prev;
      }).apply
        "determinate-darwin-tests"
        upstream
    else
      upstream;
}
