{
  lib,
  pkgs,
  inputs,
}:
let
  pkgsVSCode = import inputs.nixpkgs {
    inherit (pkgs) system;
    config.allowUnfree = true;
    overlays = [ inputs.vscode-extensions.overlays.default ];
  };

  # For two attribute sets `preferred` and `fallback`, where the first depth of
  # each is a namespace and the second depth is the name of a derivation,
  # merge them together choosing derivations from `preferred` if it occurs in both.
  mergeExtensionAttrs =
    preferred: fallback:
    lib.recursiveUpdateUntil (
      path: a: b:
      let
        aIsDrv = lib.isDerivation a;
        bIsDrv = lib.isDerivation b;
      in
      assert lib.assertMsg (aIsDrv -> bIsDrv && bIsDrv -> aIsDrv) ''
        Found two attributes at equal depth where one is not a derivation.
        Offending attribute path: `${lib.concatStringsSep "." path}`
      '';
      aIsDrv && bIsDrv
    ) fallback preferred;
in
rec {
  nixpkgs-extensions = pkgs.vscode-extensions;
  release = pkgsVSCode.vscode-marketplace-release;
  preRelease = pkgsVSCode.vscode-marketplace;
  preferPreRelease = mergeExtensionAttrs preRelease release;
  preferNixpkgsThenPreRelease = mergeExtensionAttrs nixpkgs-extensions preferPreRelease;
  preferNixpkgsThenRelease = mergeExtensionAttrs nixpkgs-extensions release;
  extraCompatible = (pkgsVSCode.forVSCodeVersion pkgs.vscode.version).vscode-marketplace-release;
}
