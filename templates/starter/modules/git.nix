{
  programs.git = {
    enable = true;
    settings = {
      # Set user.name and user.email in home.nix when you are ready to commit.
      init.defaultBranch = "main";
      fetch.prune = true;
      pull.ff = "only";
      merge.conflictStyle = "zdiff3";
      alias.st = "status --short --branch";
    };
    ignores = [
      ".DS_Store"
      "*~"
      "*.swp"
    ];
  };
}
