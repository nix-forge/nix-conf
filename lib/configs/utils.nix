_: {
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
      nixpkgsSource,
      nixpkgsArgs ? { },
    }:
    {
      nixpkgs = {
        hostPlatform = { inherit system; };
        flake.source = nixpkgsSource;
      }
      // nixpkgsArgs;
    };
}
