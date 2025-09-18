{
  emailConfig ? { },
  ...
}:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs.stdenv) isLinux isDarwin;

  # Email Config
  emailConfigPath = "${config.xdg.configHome}/git/.gitconfig-email";
  makeEmailConfigVariations = website: emailPath: ''
    [includeIf "hasconfig:remote.*.url:https://${website}/**"]
      path = "${emailPath}"

    [includeIf "hasconfig:remote.*.url:http://${website}/**"]
      path = "${emailPath}"

    [includeIf "hasconfig:remote.*.url:git@${website}:*/**"]
      path = "${emailPath}"

    [includeIf "hasconfig:remote.*.url:ssh://git@${website}/**"]
      path = "${emailPath}"

    [includeIf "hasconfig:remote.*.url:ssh://${website}/**"]
      path = "${emailPath}"
  '';
  createEmailConfig =
    websiteEmailPairs:
    lib.pipe websiteEmailPairs [
      (lib.attrsets.mapAttrsToList makeEmailConfigVariations)
      (builtins.concatStringsSep "\n")
    ];
in
{
  # Remove existing .gitconfig to avoid conflicts with runtime include
  home.activation.removeExistingGitconfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    rm -f ${config.home.homeDirectory}/.gitconfig
  '';

  programs.git = {
    enable = true;

    userName = null;
    userEmail = null;

    package = pkgs.git.override {
      osxkeychainSupport = isDarwin;
      withLibsecret = isLinux;
    };

    maintenance.enable = true;

    # Commit signing using SSH key (much easier than GPG)
    # TODO: configure the ssh key to be used for signing in the function input to this file
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
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [ ".DS_Store" ]
    ++ lib.optionals config.programs.direnv.enable [ ".direnv/" ];

    # Extra global Git config options
    extraConfig = {
      ## Credential Helpers
      credential.helper =
        if isDarwin then
          "osxkeychain"
        else if isLinux then
          lib.getExe' config.programs.git.package "git-credential-libsecret"
        else
          null;

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
      # Default Username and Email
      { inherit (config.age.secrets.gitconfig-userName) path; }
      { inherit (config.age.secrets.gitconfig-userEmail) path; }

      # Website specific email config
      { path = emailConfigPath; }
    ];
  };

  # Email Config for website specific git emails
  home.file.${emailConfigPath}.text = createEmailConfig emailConfig;
}
