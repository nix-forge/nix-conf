{ inputs, pkgs }:
let
  # Exercise the reusable selector without any host-local modules. A second
  # host must not inherit the desktop's GPU, network, or account policy.
  generic = inputs.nixpkgs.lib.nixosSystem {
    inherit (pkgs.stdenv.hostPlatform) system;
    modules = [
      ../../modules/nixos/gaming/default.nix
      { nixpkgs.config.allowUnfree = true; }
    ];
  };
  inherit (generic) config;
in
assert config.programs.steam.enable;
assert config.programs.gamescope.enable;
assert !config.services.sunshine.enable;
assert !(pkgs.lib.hasInfix "Sunshine" config.networking.firewall.extraInputRules);
pkgs.runCommand "gaming-selection" { } "touch $out"
