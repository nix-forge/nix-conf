{ ... }:
{
  programs.zsh = {
    enable = true;

    # Default Plugins
    autosuggestion.enable = true;
    enableCompletion = true;
    historySubstringSearch.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 99999;
      save = 99999;
    };

    # Oh My Zsh Plugins
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
    };
  };
}
