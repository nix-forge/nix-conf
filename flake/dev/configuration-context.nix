{ configurationInputs, ... }: {
  perSystem = { system, ... }: {
    # Keep production overlays and their package set on the same revision.
    # The ordinary perSystem pkgs remains available for development tools.
    _module.args.configurationPkgs = import configurationInputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  };
}
