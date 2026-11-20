# The remote verifier must be a trusted native package, not snapshot-supplied code.
{ pkgs, ... }: {
  home.packages = [ (import ../../../flake/runtime-packages.nix { inherit pkgs; }).macSource ];
}
