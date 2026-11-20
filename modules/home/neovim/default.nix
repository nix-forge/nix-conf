{ inputs, ... }: {
  key = "nix-conf/neovim/homeManager";
  imports = [ inputs.nvf.homeModules.default ];
  config.programs.nvf = {
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
