{ lib, ... }:
let
  mkNixpkgsLocalSystem =
    {
      system,
      darwinSdkVersion ? null,
      darwinMinVersion ? null,
    }:
    {
      inherit system;
    }
    // lib.optionalAttrs (lib.hasSuffix "-darwin" system && darwinSdkVersion != null) {
      inherit darwinSdkVersion;
    }
    // lib.optionalAttrs (lib.hasSuffix "-darwin" system && darwinMinVersion != null) {
      inherit darwinMinVersion;
    };

  mkNixpkgsOverlays = _system: overlays: overlays;

  mkNixpkgsImportArgs =
    {
      system,
      darwinSdkVersion ? null,
      darwinMinVersion ? null,
      nixpkgsArgs ? { },
    }:
    let
      overlays = mkNixpkgsOverlays system (nixpkgsArgs.overlays or [ ]);
    in
    {
      localSystem = mkNixpkgsLocalSystem { inherit system darwinSdkVersion darwinMinVersion; };
      inherit overlays;
    }
    // removeAttrs nixpkgsArgs [ "overlays" ];
in
{
  inherit mkNixpkgsImportArgs mkNixpkgsLocalSystem mkNixpkgsOverlays;

  # Build nixpkgs configuration module
  #
  # Type: String -> [Overlay] -> AttrSet -> Path -> AttrSet
  #
  # Creates a module that configures nixpkgs with:
  # - Host platform based on system
  # - Flake source for reproducibility
  # - Optional overlays
  # - User-provided nixpkgs arguments
  mkNixpkgsConfig =
    {
      system,
      darwinSdkVersion ? null,
      darwinMinVersion ? null,
      nixpkgsSource,
      nixpkgsArgs ? { },
    }:
    let
      overlays = mkNixpkgsOverlays system (nixpkgsArgs.overlays or [ ]);
    in
    {
      nixpkgs = {
        hostPlatform = mkNixpkgsLocalSystem { inherit system darwinSdkVersion darwinMinVersion; };
        flake.source = nixpkgsSource;
        inherit overlays;
      }
      // removeAttrs nixpkgsArgs [ "overlays" ];
    };
}
