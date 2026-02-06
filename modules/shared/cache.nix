let
  settings = {
    builders-use-substitutes = true;

    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://cache.garnix.io"
    ];

    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
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
      usingDeterminateNix = lib.hasAttr "determinateNix" config;
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
