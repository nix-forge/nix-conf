{ pkgs, ... }:
let
  ccSuffix = pkgs.lib.replaceStrings [ "-" ] [ "_" ] pkgs.stdenv.hostPlatform.config;
in
{
  reason = "The unwrapped Swift driver does not forward cc-wrapper hardening flags to its Clang importer.";
  upstream = "https://github.com/NixOS/nixpkgs/pull/566624";
  removal = "The pinned Swift compiler forwards cc-wrapper hardening flags to Clang and passes the native probe.";
  reviewedRevision = "1d060086d60cb76a40cf37109f979d88a5bd6396";
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
