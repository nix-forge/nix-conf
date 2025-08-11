{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs.stdenv) isLinux isDarwin;
in
{
  # Remove existing .gitconfig to avoid conflicts with runtime include
  home.activation.removeExistingGitconfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    rm -f ${config.home.homeDirectory}/.gitconfig
  '';

  programs.git = {
    enable = true;

    package = pkgs.git.override {
      osxkeychainSupport = isDarwin;
      withLibsecret = isLinux;
    };

    maintenance.enable = true;

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
      ## Basic Settings

      init.defaultBranch = "main";

      fetch.prune = true;
      commit.verbose = true;

      pull.rebase = true;
      rebase.autoStash = true;
      rebase.autosquash = true;
      rebase.updateRefs = true;
      merge.conflictStyle = "zdiff3";

      push.followTags = true;
      push.autoSetupRemote = true;
      push.default = "simple";

      ## Enable Performance Enhancements

      # set protocol version to 2 for better performance if version greater than 2.18.0
      protocol.version = lib.mkIf (lib.versionAtLeast config.programs.git.package.version "2.18.0") 2;

      core.fsmonitor = true;
      core.untrackedCache = true;
      feature.manyFiles = true;
      gc.writeCommitGraph = true;
      fetch.writeCommitGraph = true;
      index.threads = 0;

      ## Miscellaneous Settings

      core.autocrlf = "input";

      submodule.recurse = true;
      fetch.recurseSubmodules = "on-demand";
      diff.submodule = "log";

      core = {
        editor = lib.mkIf (config.home.sessionVariables ? EDITOR) config.home.sessionVariables.EDITOR;
        whitespace = "trailing-space,space-before-tab";
      };

      gpg.ssh.allowedSignersFile = config.age.secrets.git-allowedSigners.path; # Use the generated allowed_signers file
    };

    # Includes
    includes = [
      {
        path = config.age.secrets.gitconfig-userName.path;
      }
      {
        path = config.age.secrets.gitconfig-userEmail.path;
      }
      {
        path = "${config.xdg.configHome}/git/.gitconfig-github-email";
      }
    ];
  };

  home.file."${config.xdg.configHome}/git/.gitconfig-github-email".text = ''
    [includeIf "hasconfig:remote.*.url:https://github.com/**"]
      path = ${config.age.secrets.gitconfig-userEmail-GitHub.path}

    [includeIf "hasconfig:remote.*.url:http://github.com/**"]
      path = ${config.age.secrets.gitconfig-userEmail-GitHub.path}

    [includeIf "hasconfig:remote.*.url:git@github.com:*/**"]
      path = ${config.age.secrets.gitconfig-userEmail-GitHub.path}

    [includeIf "hasconfig:remote.*.url:ssh://git@github.com/**"]
      path = ${config.age.secrets.gitconfig-userEmail-GitHub.path}

    [includeIf "hasconfig:remote.*.url:ssh://github.com/**"]
      path = ${config.age.secrets.gitconfig-userEmail-GitHub.path}



    [includeIf "hasconfig:remote.*.url:https://gist.github.com/**"]
      path = ${config.age.secrets.gitconfig-userEmail-GitHub.path}

    [includeIf "hasconfig:remote.*.url:ssh://git@gist.github.com/**"]
      path = ${config.age.secrets.gitconfig-userEmail-GitHub.path}

    [includeIf "hasconfig:remote.*.url:git@gist.github.com:*/**"]
      path = ${config.age.secrets.gitconfig-userEmail-GitHub.path}
  '';
}
