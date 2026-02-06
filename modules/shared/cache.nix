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
  nixos = { inherit settings; };

  darwin =
    { lib, config, ... }:
    lib.mkMerge [
      (lib.mkIf (config.nix.enable) { nix = { inherit settings; }; })
      (lib.mkIf (lib.hasAttr "determinateNix" config) {
        determinateNix.customSettings = settings;
      })
    ];

  homeManager = { inherit settings; };
}
