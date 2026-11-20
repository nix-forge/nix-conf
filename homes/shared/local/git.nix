{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
{
  programs.git = {
    # Home Manager owns the only maintenance scheduler on both platforms.
    # The worktree module discovers additional durable clones at run time.
    maintenance.enable = lib.mkDefault true;
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
      (
        myLib.writers.renderBashText { inherit pkgs; }
          {
            name = "remove-legacy-git-privacy-config.sh";
            text = ''
              # shellcheck shell=bash
              bootstrap=@lib_escapeShellArg_config_xdg_stateHome_git_privacy_bootstra@
              global_config=@lib_escapeShellArg_config_home_homeDirectory_gitconfig@
              if test -f "$global_config" && @lib_getExe_pkgs_git_git@ config --file "$global_config" \
                --fixed-value --get-all include.path "$bootstrap" >/dev/null; then
                run @lib_getExe_pkgs_git_git@ config --file "$global_config" \
                  --fixed-value --unset-all include.path "$bootstrap"
              fi
              run @lib_getExe_pkgs_coreutils_rm@ -f -- \
                @lib_escapeShellArg_config_xdg_configHome_jj_conf_d_99_git_pr@
            '';
          }
          {
            lib_escapeShellArg_config_xdg_stateHome_git_privacy_bootstra = lib.escapeShellArg "${config.xdg.stateHome}/git-privacy/bootstrap/config";
            lib_escapeShellArg_config_home_homeDirectory_gitconfig = lib.escapeShellArg "${config.home.homeDirectory}/.gitconfig";
            lib_getExe_pkgs_git_git = lib.getExe' pkgs.git "git";
            lib_getExe_pkgs_coreutils_rm = lib.getExe' pkgs.coreutils "rm";
            lib_escapeShellArg_config_xdg_configHome_jj_conf_d_99_git_pr = lib.escapeShellArg "${config.xdg.configHome}/jj/conf.d/99-git-privacy-bootstrap.toml";
          }
      );
}
