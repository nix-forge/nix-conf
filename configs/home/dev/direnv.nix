_args: {
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    # nix-direnv.package = inputs.nix-direnv.packages.${system}.default.override (
    #   let
    #     nixPackage =
    #       if pkgs.stdenv.hostPlatform.isDarwin && darwinNixEnabled then
    #         args.darwinConfig.nix.package
    #       else
    #         inputs.determinate.inputs.nix.packages.${system}.default;
    #   in
    #   {
    #     nix = nixPackage;
    #   }
    # );
  };
}
