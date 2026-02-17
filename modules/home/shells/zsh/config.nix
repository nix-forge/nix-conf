{ lib, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  home.shell.enableZshIntegration = true;
  programs.zsh = {
    enable = true;

    enableCompletion = true;
    enableVteIntegration = lib.mkIf isLinux true;
    autocd = true;
    autosuggestion.enable = true;
    historySubstringSearch.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 99999;
      save = 99999;
      expireDuplicatesFirst = true;
      extended = true;
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
    };
  };
}
