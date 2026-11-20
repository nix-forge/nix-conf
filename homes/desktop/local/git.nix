{ config, lib, ... }:
let
  inherit (import ../../../hosts/nixos/desktop/local/storage/.storage-roles.nix) workMount;
in
{
  imports = [ ../../shared/local/git.nix ];
  programs.dev-worktree = {
    worktreeMount = workMount;
    worktreeRoot = "${workMount}/projects/worktrees";
  };
  xdg.directoryBookmarks.entries = lib.mkAfter [
    {
      path = config.programs.dev-worktree.worktreeRoot;
      label = "Worktrees";
    }
  ];
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
