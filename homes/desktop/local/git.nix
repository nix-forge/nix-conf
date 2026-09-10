{ config, ... }: {
  imports = [ ../../shared/git.nix ];
  programs.git = {
    maintenance = {
      enable = true;
      repositories = [
        "${config.home.homeDirectory}/Developer/nix-conf"
        "${config.home.homeDirectory}/Developer/nix-conf/nix-config-framework"
        "${config.home.homeDirectory}/Developer/nix-conf/nix-seal"
        "${config.home.homeDirectory}/Developer/nix-conf/pkgs"
      ];
    };
  };
}
