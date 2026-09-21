{ config, ... }: {
  imports = [ ../../shared/git.nix ];
  programs.git = {
    maintenance = {
      enable = true;
      repositories = [
        "${config.home.homeDirectory}/Developer/nix-conf"
        "${config.home.homeDirectory}/Developer/ci"
        "${config.home.homeDirectory}/Developer/nix-forge-community"
        "${config.home.homeDirectory}/Developer/nix-homelab"
        "${config.home.homeDirectory}/Developer/vpn-confinement"
        "${config.home.homeDirectory}/Developer/nix-conf/nix-config-framework"
        "${config.home.homeDirectory}/Developer/nix-conf/nix-homelab"
        "${config.home.homeDirectory}/Developer/nix-conf/nix-seal"
        "${config.home.homeDirectory}/Developer/nix-conf/pkgs"
      ];
    };
  };
}
