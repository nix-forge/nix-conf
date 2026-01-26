{ pkgs, ... }:
{
  home.packages = [
    pkgs.libreoffice-qt

    # Spellcheck
    pkgs.hunspell
    pkgs.hunspellDicts.en_US
  ];
}
