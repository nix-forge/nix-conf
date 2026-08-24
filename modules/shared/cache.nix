let
  settings = {
    builders-use-substitutes = true;

    # A trusted-substituter only authorizes an untrusted client to request a
    # cache; it does not make the daemon use that cache. Configure this signed
    # cache explicitly so the key already trusted below improves build reuse.
    substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
    ];

    trusted-substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
    ];

    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
in
{
  nixos = {
    nix = { inherit settings; };
  };

  darwin =
    { lib, config, ... }:
    let
      usingDeterminateNix = lib.hasAttr "determinateNix" config && config.determinateNix.enable;
    in
    lib.mkMerge [
      (lib.mkIf (!usingDeterminateNix) { nix = { inherit settings; }; })
      (lib.mkIf usingDeterminateNix { determinateNix.customSettings = settings; })
    ];

  homeManager =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    {
      nix = {
        package = lib.mkDefault pkgs.nix;
        settings = lib.mkIf (config.nix.package != null) settings;
      };
    };
}
