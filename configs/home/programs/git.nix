{
  config,
  lib,
  ...
}:
{
  # Remove existing .gitconfig to avoid conflicts with runtime include
  home.activation.removeExistingGitconfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    rm -f ${config.home.homeDirectory}/.gitconfig
  '';

  # Generate allowed_signers file at runtime
  home.activation.gitAllowedSigners = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ${config.xdg.configHome}/git
    rm -f ${config.xdg.configHome}/git/allowed_signers
    echo "$(cat ${config.age.secrets.git-userEmail.path}) namespaces="git" $(cat ${config.home.homeDirectory}/.ssh/id_ed25519.pub)" > ${config.xdg.configHome}/git/allowed_signers
  '';

  programs.git = {
    enable = true;

    # Commit signing using SSH key (much easier than GPG)
    signing = {
      format = "ssh";
      key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
      signByDefault = true; # Always sign commits and tags
    };

    # Handy Git aliases for smoother CLI usage
    aliases = {
      co = "checkout";
      br = "branch";
      ci = "commit";
      st = "status";
      lg = "log --oneline --graph --all";
    };

    # Git attributes for custom diff/merge handling
    attributes = [ "*.pdf diff=pdf" ];

    # Enable delta for beautiful side-by-side diffs
    delta = {
      enable = true;
      options = {
        diff-so-fancy = true;
        line-numbers = true;
        true-color = "always";
      };
    };

    # Enable Git LFS (Large File Support) for handling big binary blobs
    lfs.enable = true;

    # Global ignores for files you never want to track
    ignores = [
      "*~"
      "*.swp"
      ".DS_Store"
    ]
    ++ lib.optionals (config.programs.direnv.enable) [
      ".direnv/"
    ];

    # Extra global Git config options
    extraConfig = {
      core = {
        editor = "nvim"; # Use Neovim as Git commit/message editor #TODO: change to $EDITOR
        whitespace = "trailing-space,space-before-tab";
      };
      push.autoSetupRemote = true;
      pull.rebase = true; # `git pull` will rebase by default
      push.default = "simple"; # Only push current branch to matching remote branch
      init.defaultBranch = "main"; # Set default branch name on new repos
      gpg.ssh.allowedSignersFile = "${config.xdg.configHome}/git/allowed_signers"; # Use the generated allowed_signers file
    };

    # Includes
    includes = [
      {
        path = config.age.secrets.gitconfig-userName.path;
      }
      {
        path = config.age.secrets.gitconfig-userEmail.path;
      }
    ];
  };
}
