_: {
  lib.targetPackagePolicy =
    inputs: (import ../../../hosts/shared/local/package-policy.nix) inputs { allowUnfree = true; };
}
