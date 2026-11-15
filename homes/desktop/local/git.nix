{ config, ... }: {
  imports = [ ../../shared/local/git.nix ];
  programs.dev-worktree.extraInstructions = ''
    On the desktop host, run heavy evaluation, builds, and checks through
    `workstation-task`, including work from task checkouts.
  '';
  programs.dev-worktree.workloadPrefix = [ "${config.home.profileDirectory}/bin/workstation-task" ];
  programs.git = {
    maintenance = {
      enable = true;
      repositories = [
        "${config.home.homeDirectory}/Developer/personal/nix-conf"
        "${config.home.homeDirectory}/Developer/personal/nix-conf/nix-config-framework"
        "${config.home.homeDirectory}/Developer/personal/nix-conf/nix-homelab"
        "${config.home.homeDirectory}/Developer/personal/nix-conf/nix-seal"
        "${config.home.homeDirectory}/Developer/personal/nix-conf/pkgs"
        "${config.home.homeDirectory}/Developer/personal/nixpkgs"
      ];
    };
  };
}
