{ pkgs, ... }:
let
  signer = (import ../../flake/runtime-packages.nix { pkgs = pkgs.buildPackages; }).signSignalBundle;
in
{
  reason = "Stripping invalidates AeroSpace and Zoom vendor signatures; Signal packaging leaves completed bundles unsealed.";
  upstream = "https://github.com/NixOS/nixpkgs/tree/7fd4004d0511991fff3a0524856a9be09e28c5f0/pkgs/by-name";
  removal = "The pinned recipes preserve AeroSpace and Zoom signatures and seal the final Signal bundle with its required entitlements; all pass native strict deep verification.";
  reviewedRevision = "04906337b6d53e8bb0eaf0470ae9f070a4d4eb55";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      dontStrip =
        if
          builtins.elem old.pname [
            "aerospace"
            "zoom"
          ]
        then
          true
        else
          old.dontStrip or false;
      nativeBuildInputs =
        (old.nativeBuildInputs or [ ])
        ++ pkgs.lib.optionals (old.pname == "signal-desktop") [ pkgs.rcodesign ];
      postFixup =
        (old.postFixup or "")
        + pkgs.lib.optionalString (old.pname == "signal-desktop") ''
          ${pkgs.lib.getExe signer} "$out/Applications/Signal.app" "${old.src}/build"
        '';
      signalSignatureSigner = pkgs.lib.optionalString (old.pname == "signal-desktop") (
        pkgs.lib.getExe signer
      );
    });
}
