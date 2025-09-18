{ inputs, ... }:
{
  imports = [
    inputs.nixvim.homeManagerModules.nixvim

    ./config
  ];

  programs.nixvim = {
    enable = true;

    # Aliases
    viAlias = true;
    vimAlias = true;

    # Clipboard
    clipboard = {
      # Enable clipboard support
      providers.wl-copy.enable = true;

      # Allow copying to the system clipboard
      register = "unnamedplus";
    };
  };
}
