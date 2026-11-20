{ pkgs, ... }: {
  # Keep structural diffs available as `difft` without changing Git's defaults.
  home.packages = [ pkgs.difftastic ];
}
