{
  home.shell.enableZshIntegration = true;
  programs.zsh = {
    enable = true;

    autosuggestion.enable = true;
    enableCompletion = true;
    historySubstringSearch.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 99999;
      save = 99999;
    };

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
    };
  };
}
