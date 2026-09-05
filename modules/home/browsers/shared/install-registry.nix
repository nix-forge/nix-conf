{ lib, pkgs, ... }: {
  options.programs.browserSuite.shared.geckoInstallRegistry.reconciler = lib.mkOption {
    type = lib.types.package;
    internal = true;
    readOnly = true;
    default = pkgs.writers.writePython3Bin "hm-reconcile-gecko-install-registry" { } (
      builtins.readFile ./reconcile_install_registry.py
    );
    description = "Helper that points Gecko installation IDs at a managed profile.";
  };
}
