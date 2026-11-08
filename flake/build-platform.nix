{ inputs, lib, ... }: {
  perSystem = { system, ... }: {
    # Ordinary outputs stay native. Explicit packagesFor calls select cross
    # platform pairs without overriding a consumer's package set.
    _module.args.pkgs = lib.mkOverride 900 (import inputs.nixpkgs (import ./platform-args.nix system));
  };
}
