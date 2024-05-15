{
  pkgs,
  config,
  lib,
  ...
}:
let
  p10k_config = "${config.home.homeDirectory}/.p10k.zsh";
in
{
  programs.zsh = {
    enable = true;

    # Default Plugins
    autosuggestion.enable = true;
    enableCompletion = true;
    historySubstringSearch.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      "ls" = "ls --color --group-directories-first";
    };

    history = {
      size = 99999;
      save = 99999;
    };

    # Oh My Zsh Plugins
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
    };

    # More Plugins
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];

    initExtra = ''
      # Powerlevel10k Configuration
      [[ ! -f ${p10k_config} ]] || source ${p10k_config}

      # VSCode Shell Integration
      [[ "$TERM_PROGRAM" == "vscode" ]] && . "$(NIXOS_OZONE_WL= ${lib.getExe config.programs.vscode.package} --locate-shell-integration-path zsh)"

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
      fi
    '';
  };

  home.file."${p10k_config}".source = ./.p10k.zsh;
}
