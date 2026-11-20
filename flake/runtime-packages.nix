{ pkgs }:
let
  workspace = import ./rust-workspace.nix { inherit pkgs; };
in
workspace.packages // { inherit (workspace) source; }
