{
  config,
  lib,
  pkgs,
  ...
}:
let
  templates = config.nixSeal.templates;
  guard = pkgs.writers.writePython3Bin "git-privacy-hook" {
    # Match Ruff's formatting of long lines, slices, and binary operators.
    flakeIgnore = [
      "E203"
      "E501"
      "W503"
    ];
  } ../../modules/home/dev/scripts/git-privacy-hook.py;
  # A global hooksPath replaces .git/hooks. Forward every client hook so
  # existing prek and Git LFS installations continue to run.
  hookNames = [
    "applypatch-msg"
    "pre-applypatch"
    "post-applypatch"
    "pre-commit"
    "pre-merge-commit"
    "prepare-commit-msg"
    "commit-msg"
    "post-commit"
    "pre-rebase"
    "post-checkout"
    "post-merge"
    "pre-push"
    "post-rewrite"
    "pre-auto-gc"
    "post-index-change"
    "reference-transaction"
    "sendemail-validate"
    "fsmonitor-watchman"
    "p4-changelist"
    "pre-receive"
    "update"
    "proc-receive"
    "post-receive"
    "post-update"
    "push-to-checkout"
    "p4-prepare-changelist"
    "p4-post-changelist"
    "p4-pre-submit"
  ];
  hooks = pkgs.linkFarm "git-privacy-hooks" (
    map (name: {
      inherit name;
      path = pkgs.writeShellScript name ''
        exec ${lib.getExe guard} --git ${lib.getExe' config.programs.git.package "git"} \
          --gh ${lib.getExe pkgs.gh} ${lib.escapeShellArg name} "$@"
      '';
    }) hookNames
  );
in
{
  programs.git = {
    signing = {
      format = "ssh";
      key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
      signByDefault = true;
    };
    settings = {
      # Safe even in a new repository with no remote or rendered secrets.
      user = {
        email = "72767437+IanHollow@users.noreply.github.com";
        useConfigOnly = true;
      };
      core.hooksPath = toString hooks;
      privacy.policyFile = config.nixSeal.secrets.git-privacy-policy.path;
      gpg.ssh.allowedSignersFile = templates.git-allowedsigners.path;
    };
    includes = [ { path = templates.gitconfig-username.path; } ];
  };

  # Retire only this feature's temporary protection after the sealed policy
  # and both managed identities have activated successfully.
  home.activation.gitPrivacyBootstrap =
    lib.hm.dag.entryAfter [ "nixSeal" "linkGeneration" "jujutsuLocalIdentity" ]
      ''
        bootstrap=${lib.escapeShellArg "${config.xdg.stateHome}/git-privacy/bootstrap/config"}
        global_config=${lib.escapeShellArg "${config.home.homeDirectory}/.gitconfig"}
        if test -f "$global_config" && ${lib.getExe' pkgs.git "git"} config --file "$global_config" \
          --fixed-value --get-all include.path "$bootstrap" > /dev/null; then
          run ${lib.getExe' pkgs.git "git"} config --file "$global_config" \
            --fixed-value --unset-all include.path "$bootstrap"
        fi
        run ${lib.getExe' pkgs.coreutils "rm"} -f -- \
          ${lib.escapeShellArg "${config.xdg.configHome}/jj/conf.d/99-git-privacy-bootstrap.toml"}
      '';
}
