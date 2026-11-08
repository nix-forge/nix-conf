_: {
  lib.targetPackagePolicy = inputs: {
    overlays = [ (import ../../../../overlays { inherit inputs; }) ];
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
      allowVariants = true;
      allowBroken = false;
      # allowAliases = false;

      # GPU acceleration is selected by its consumer. Global CUDA changes
      # unrelated package variants and their binary-cache coverage.
      cudaSupport = false;
    };
  };
}
