{ inputs, lib, ... }:
let
  fixes = import ../../../overlays/temporary { inherit inputs lib; };
in
{
  imports = [
    inputs.nvf.homeManagerModules.default
    (fixes.apply "stylix-nvf" inputs.stylix)
  ];
  programs.nvf = {
    enable = true;
    settings = {
      vim = {
        viAlias = true;
        vimAlias = true;
        lsp.enable = true;
      };
    };
  };
}
