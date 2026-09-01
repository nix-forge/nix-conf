{ pkgs, ... }: {
  # `glab auth login` maintains host metadata and uses the OS keyring when it
  # is available. Keep that state outside the Nix store and Home Manager links.
  home.packages = [ pkgs.glab ];
}
