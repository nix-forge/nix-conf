{ inputs, ... }:
{
  imports = [ inputs.nix-gaming.nixosModules.platformOptimizations ];

  programs.steam = {
    platformOptimizations.enable = true;
  };
}
