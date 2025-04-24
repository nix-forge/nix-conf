{
  inputs,
  pkgs,
  ...
}:
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    nix-direnv.package = inputs.nix-direnv.packages.${pkgs.system}.default;
  };
}
