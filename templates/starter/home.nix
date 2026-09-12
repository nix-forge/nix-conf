{ pkgs, ... }: {
  imports = [
    ./modules/git.nix
    ./modules/shell.nix
    ./modules/prompt.nix
  ];

  home = {
    # Replace these two values before activating on your own account.
    username = "learner";
    homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/learner" else "/home/learner";

    # Keep this at the version used for your first activation. Input updates do
    # not require changing it; see Home Manager's release notes before doing so.
    stateVersion = "26.05";
  };
  programs.home-manager.enable = true;
}
