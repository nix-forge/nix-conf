{ config, lib, ... }:
let
  caches = {
    extra-substituters = [
      "https://cache.nixos.org" # official nix cache
      "https://nix-community.cachix.org" # nix-community cache
      "https://nixpkgs-unfree.cachix.org" # unfree-package cache
      "https://cache.garnix.io" # garnix binary cache
    ];

    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
  };
in
lib.mkMerge [
  (lib.mkIf config.nix.enable {
    nix.settings = caches;
  })
  (lib.mkIf (!config.nix.enable) {
    determinate-nix.customSettings = caches;
  })
]
