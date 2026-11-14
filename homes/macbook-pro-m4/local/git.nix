{ ... }: {
  imports = [ ../../shared/local/git.nix ];
  # Discover durable repositories on this host at each maintenance run.
  # This host builds verified exports and has no local configuration clone.
  programs.git.maintenance.enable = true;
}
