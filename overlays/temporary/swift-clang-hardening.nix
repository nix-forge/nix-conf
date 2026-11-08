{ pkgs, ... }:
let
  ccSuffix = pkgs.lib.replaceStrings [ "-" ] [ "_" ] pkgs.stdenv.hostPlatform.config;
in
{
  reason = "The unwrapped Swift driver does not forward cc-wrapper hardening flags to its Clang importer.";
  upstream = "https://github.com/NixOS/nixpkgs/pull/566624";
  removal = "The pinned Swift compiler forwards cc-wrapper hardening flags to Clang and passes the native probe.";
  reviewedRevision = "02c087f3fe673c9e317f206a627cb6b910336dbe";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      buildCommand =
        old.buildCommand
        + ((import ../../lib/templates/text.nix) ./scripts/install-swift-hardening-wrapper.sh {
          pkgs_bash = pkgs.bash;
          inherit ccSuffix;
          pkgs_stdenv_cc = pkgs.stdenv.cc;
        });
    });
}
