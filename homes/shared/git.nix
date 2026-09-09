{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.git = {
    signing = {
      format = "ssh";
      key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
      signByDefault = true;
    };
    settings = {
      user.useConfigOnly = true;
      gpg.ssh.allowedSignersFile = config.nixSeal.templates.git-allowedsigners.path;
    };
    # One public identity source for Git and Jujutsu. Missing secrets stop
    # commits through useConfigOnly instead of falling back to a machine address.
    includes = [
      { path = config.nixSeal.templates.gitconfig-username.path; }
      { path = config.nixSeal.templates.gitconfig-useremail-github.path; }
    ];
    emailPrivacy = {
      enable = true;
      policyFile = config.nixSeal.secrets.git-privacy-policy.path;
    };
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
