{ inputs, ... }:
{
  imports = [ inputs.nix-gaming.nixosModules.platformOptimizations ];

  programs.steam = {
    enable = true;
    platformOptimizations.enable = true;
  };
}
