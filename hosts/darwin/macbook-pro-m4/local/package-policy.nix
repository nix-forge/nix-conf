_: {
  lib.targetPackagePolicy =
    inputs: (import ../../../shared/local/package-policy.nix) inputs { allowUnfree = true; };
}
