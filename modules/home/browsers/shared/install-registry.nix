{ lib, pkgs, ... }: {
  options.programs.browserSuite.shared.geckoInstallRegistry.reconciler = lib.mkOption {
    type = lib.types.package;
    internal = true;
    readOnly = true;
    default = (import ../../../../flake/runtime-packages.nix { inherit pkgs; }).geckoInstallRegistry;
    description = "Helper that points Gecko installation IDs at a managed profile.";
  };
}
