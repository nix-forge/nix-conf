{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config.age.secrets) gitUserName gitUserEmail;
in
{
  # Remove existing .gitconfig to avoid conflicts with runtime include
  home.activation.removeExistingGitconfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    rm -f ${config.home.homeDirectory}/.gitconfig
  '';

  # Create a runtime-generated Git config file with user.name and user.email
  home.activation.gitUserIdentity = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ${config.xdg.configHome}/git
    cat > ${config.xdg.configHome}/git/identity.gitconfig <<EOF
    [user]
            name = $(cat ${gitUserName.path})
            email = $(cat ${gitUserEmail.path})
    EOF
  '';

  # Generate allowed_signers file at runtime
  home.activation.gitAllowedSigners = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ${config.xdg.configHome}/git
    echo "$(cat ${gitUserEmail.path}) namespaces=\"git\" $(cat ${config.home.homeDirectory}/.ssh/id_ed25519.pub)" > ${config.xdg.configHome}/git/allowed_signers
  '';

  # create a service to check that the git config files are present
  systemd.user.services.gitconfig = {
    Unit = {
      Description = "Configure-Git";
      Wants = [ "default.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "gitConfigSetup" ''
        #!/run/current-system/sw/bin/bash

        mkdir -p ${config.xdg.configHome}/git

        cat > ${config.xdg.configHome}/git/identity.gitconfig <<EOF
        [user]
                name = $(cat ${gitUserName.path})
                email = $(cat ${gitUserEmail.path})
        EOF

        echo "$(cat ${gitUserEmail.path}) namespaces=\"git\" $(cat ${config.home.homeDirectory}/.ssh/id_ed25519.pub)" > ${config.xdg.configHome}/git/allowed_signers
      ''}";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  programs.git = {
    enable = true;

    # Use gitFull for extra features like send-email, credential support, etc.
    package = pkgs.gitFull;

    # Leave these null since we're injecting them via runtime include
    userName = null;
    userEmail = null;

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
    attributes = [
      "*.pdf diff=pdf"
    ];

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
      ".direnv/"
      "node_modules/"
    ];

    # Extra global Git config options
    extraConfig = {
      core = {
        editor = "nvim"; # Use Neovim as Git commit/message editor
        whitespace = "trailing-space,space-before-tab";
      };
      push.autoSetupRemote = true;
      pull.rebase = true; # `git pull` will rebase by default
      push.default = "simple"; # Only push current branch to matching remote branch
      init.defaultBranch = "main"; # Set default branch name on new repos
      gpg.ssh.allowedSignersFile = "${config.xdg.configHome}/git/allowed_signers"; # Use the generated allowed_signers file
    };

    # Include the runtime-generated identity config (with user.name/email)
    includes = [
      {
        path = "${config.xdg.configHome}/git/identity.gitconfig";
      }
    ];
  };
}
