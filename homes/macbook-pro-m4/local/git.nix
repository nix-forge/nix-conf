{ config, ... }: {
  imports = [ ../../shared/git.nix ];
  programs.git = {
    maintenance = {
      enable = true;
      repositories = [
        "${config.home.homeDirectory}/Developer/personal/nix-conf"
        "${config.home.homeDirectory}/Developer/personal/nix-conf/nix-config-framework"
        "${config.home.homeDirectory}/Developer/personal/nix-conf/nix-seal"
        "${config.home.homeDirectory}/Developer/personal/nix-conf/pkgs"
      ];
    };
  };
}
