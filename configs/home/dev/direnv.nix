{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
{
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    nix-direnv.package = inputs.nix-direnv.packages.${pkgs.system}.default;
  };

  home.file."${config.home.homeDirectory}/.zshrc-direnv-vscode-fix".text = ''
    # This is a workaround to make direnv work with VS Code's integrated terminal
    # when using the direnv extension, by making sure to reload
    # the environment the first time terminal is opened.
    #
    # See https://github.com/direnv/direnv-vscode/issues/561#issuecomment-1837462994.
    #
    # The variable VSCODE_INJECTION is apparently set by VS Code itself, and this is how
    # we can detect if we're running inside the VS Code terminal or not.
    if [[ -n "$VSCODE_INJECTION" && -z "$VSCODE_TERMINAL_DIRENV_LOADED" && -f .envrc ]]; then
        cd ..
        cd -
        export VSCODE_TERMINAL_DIRENV_LOADED=1
        clear
    fi
  '';

  home.activation = {
    removeZshBackup = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      # Remove zsh backup files
      rm -f ${config.home.homeDirectory}/.zshrc.*
    '';
    zshrcDirenvVscodeFix = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      rm -f ${config.home.homeDirectory}/.zshrc-temp
      mv ${config.home.homeDirectory}/.zshrc ${config.home.homeDirectory}/.zshrc-temp
      cat ${config.home.homeDirectory}/.zshrc-temp ${config.home.homeDirectory}/.zshrc-direnv-vscode-fix > ${config.home.homeDirectory}/.zshrc
      chmod 444 ${config.home.homeDirectory}/.zshrc
      # Remove zsh backup files and temporary files
      rm -f ${config.home.homeDirectory}/.zshrc-temp ${config.home.homeDirectory}/.zshrc.*
    '';
  };
}
