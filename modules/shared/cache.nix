let
  cacheUrls = [
    "https://cache.nixos.org/"
    "https://nix-community.cachix.org"
  ];

  cacheKeys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];

  # NixOS, non-Determinate nix-darwin, and Home Manager own their full cache
  # configuration, so these normal settings are appropriate there.
  settings = {
    builders-use-substitutes = true;

    # A trusted-substituter only authorizes an untrusted client to request a
    # cache; it does not make the daemon use that cache. Configure this signed
    # cache explicitly so the key already trusted below improves build reuse.
    substituters = cacheUrls;
    trusted-substituters = cacheUrls;
    trusted-public-keys = cacheKeys;
  };

  # Determinate Nix owns the base cache configuration, including its FlakeHub
  # endpoints used for authenticated services such as the native Linux
  # builder.  Its custom settings must extend those lists rather than replace
  # them; `determinate-nixd status` specifically diagnoses `substituters` here
  # as a configuration error.
  determinateSettings = {
    builders-use-substitutes = true;
    extra-substituters = cacheUrls;
    extra-trusted-substituters = cacheUrls;
    extra-trusted-public-keys = cacheKeys;
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
      (lib.mkIf usingDeterminateNix { determinateNix.customSettings = determinateSettings; })
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
