{ lib, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  programs.zsh = {
    enable = true;

    enableCompletion = true;
    enableVteIntegration = lib.mkIf isLinux true;
    autocd = true;
    autosuggestion.enable = true;
    autosuggestion.highlight = "fg=8";
    historySubstringSearch.enable = true;
    syntaxHighlighting.enable = true;
    defaultKeymap = "viins";

    completionInit = ''
      autoload -U compinit
      compinit -d "''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-$ZSH_VERSION"
      zstyle ':completion:*' menu select
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
      zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
    '';

    history = {
      size = 99999;
      save = 99999;
      expireDuplicatesFirst = true;
      extended = true;
      ignoreDups = true;
      ignoreSpace = true;
      ignorePatterns = [ "(ls|l|la|ll|lla|lt|lg|cd|pwd|clear|exit|history)" ];
      share = true;
    };
  };
}
