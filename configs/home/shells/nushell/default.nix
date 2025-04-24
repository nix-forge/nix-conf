{ config, ... }:
{
  programs.nushell = {
    enable = true;

    # Move home-manager settings to the nushell config
    # https://github.com/nix-community/home-manager/issues/4313
    shellAliases = config.home.shellAliases;
    environmentVariables = config.home.sessionVariables;

    settings = {
      # Remove the welcome banner message
      show_banner = false;
    };
  };
}
