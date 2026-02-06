{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;
in
{
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

    attributes = [ "*.pdf diff=pdf" ];

    lfs.enable = true;

    ignores = [
      "*~"
      "*.swp"
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ ".DS_Store" ]
    ++ lib.optionals config.programs.direnv.enable [ ".direnv/" ];

    settings = {
      credential.helper =
        if isDarwin then
          "osxkeychain"
        else if isLinux then
          lib.getExe' config.programs.git.package "git-credential-libsecret"
        else
          null;

      init.defaultBranch = "main";
      fetch = {
        prune = true;
        pruneTags = true;
        writeCommitGraph = true;
        recurseSubmodules = "on-demand";
        negotiationAlgorithm = "skipping";
        showForcedUpdates = true;
      };
      commit.verbose = true;
      commit.status = true;
      rerere.enabled = true;
      rerere.autoupdate = true;

      pull = {
        rebase = true;
      };
      branch.autoSetupRebase = "always";
      rebase = {
        autoStash = true;
        autosquash = true;
        updateRefs = true;
        rescheduleFailedExec = true;
      };
      merge = {
        autoStash = true;
        strategy = "ort";
        stat = true;
      };
      push = {
        followTags = true;
        autoSetupRemote = true;
        default = "simple";
      };
      core = {
        fsmonitor = true;
        untrackedCache = true;
        autocrlf = "input";
        editor = lib.mkIf (config.home.sessionVariables ? EDITOR) config.home.sessionVariables.EDITOR;
        whitespace = "trailing-space,space-before-tab";
        abbrev = 12;
        precomposeUnicode = isDarwin;
      };
      color.ui = "auto";
      feature.manyFiles = true;
      gc.writeCommitGraph = true;
      index.threads = 0;
      diff = {
        algorithm = "histogram";
        colorMoved = "default";
        renames = true;
        submodule = "log";
      };
      status = {
        aheadBehind = true;
        submoduleSummary = true;
      };
      submodule.recurse = true;
      help.autocorrect = "prompt";
      tag.sort = "version:refname";
      branch.sort = "-committerdate";
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
