{ pkgs, config, ... }:
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
      [[ ! -f ${p10k_config} ]] || source ${p10k_config}
    '';
  };

  home.file."${p10k_config}".source = ./.p10k.zsh;
}
