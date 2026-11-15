_: {
  lib.targetPackagePolicy = inputs: {
    overlays = [ (import ../../../../overlays { inherit inputs; }) ];
    config = {
      allowUnfree = true;
    };
  };
}
