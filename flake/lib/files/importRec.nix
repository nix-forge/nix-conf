{ lib, ... }:
let
  importDirHelper = (import ./importDirHelper.nix) { inherit lib; };
in
dir: filter:
importDirHelper dir {
  inherit filter;
  importDirDefault = false;
}
