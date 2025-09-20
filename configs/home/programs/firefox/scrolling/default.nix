{ lib }:
let
  mkPreset = file: import file { inherit lib; };
in
{
  sharpen = mkPreset ./sharpen.nix;
  instant = mkPreset ./instant.nix;
  smooth = mkPreset ./smooth.nix;
  natural = mkPreset ./natural.nix;
}
