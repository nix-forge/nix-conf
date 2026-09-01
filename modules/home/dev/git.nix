{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;
  gitPackage = pkgs.git.override {
    osxkeychainSupport = isDarwin;
    withLibsecret = isLinux;
  };
in
{
  programs.git = {
    enable = true;

    package = gitPackage;

    lfs.enable = true;

    ignores = [
      "*~"
      "*.swp"
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ ".DS_Store" ]
    ++ lib.optionals config.programs.direnv.enable [ ".direnv/" ];

    settings = {
      alias = {
        last = "log -1 HEAD";
        lg = "log --graph --decorate --oneline";
        st = "status --short --branch";
      };
      init.defaultBranch = "main";
      fetch = {
        prune = true;
        pruneTags = true;
        writeCommitGraph = true;
        recurseSubmodules = "on-demand";
        showForcedUpdates = true;
      };
      commit = {
        status = true;
        verbose = true;
      };

      rerere.enabled = true;

      pull.rebase = true;
      branch.autoSetupRebase = "always";
      rebase = {
        autosquash = true;
        updateRefs = true;
        rescheduleFailedExec = true;
      };
      merge = {
        conflictStyle = "zdiff3";
        stat = true;
      };
      push = {
        followTags = true;
        autoSetupRemote = true;
        default = "simple";
      };
      core = {
        autocrlf = "input";
        editor = lib.mkIf (config.home.sessionVariables ? EDITOR) config.home.sessionVariables.EDITOR;
        whitespace = "trailing-space,space-before-tab";
        abbrev = 12;
      }
      // lib.optionalAttrs isDarwin {
        fsmonitor = true;
        precomposeUnicode = true;
      };

      color.ui = "auto";
      feature.manyFiles = true;
      gc.writeCommitGraph = true;
      index.threads = 0;
      maintenance.strategy = "incremental";
      transfer.credentialsInUrl = "die";
      diff = {
        algorithm = "histogram";
        colorMoved = "zebra";
        renames = true;
        submodule = "log";
      };
      status = {
        aheadBehind = true;
        submoduleSummary = true;
      };
      help.autocorrect = "prompt";
      tag.sort = "version:refname";
      branch.sort = "-committerdate";
    }
    // lib.optionalAttrs isDarwin { credential.helper = "osxkeychain"; }
    // lib.optionalAttrs isLinux {
      credential.helper = lib.getExe' gitPackage "git-credential-libsecret";
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      line-numbers = true;
      true-color = "always";
      navigate = true;
      side-by-side = true;
      features = "decorations";
    };
  };
}
