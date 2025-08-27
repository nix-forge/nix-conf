{
  inputs,
  config,
  system,
  ...
}:
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    nix-direnv.package = inputs.nix-direnv.packages.${system}.default.override {
      nix = config.nix.package;
    };
  };
}
