{ lib, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  programs.bash = {
    enable = true;
    enableCompletion = true;
    enableVteIntegration = lib.mkIf isLinux true;

    historyControl = [
      "ignoreboth"
      "erasedups"
    ];
    historyIgnore = [
      "cd"
      "clear"
      "exit"
      "history"
      "ls"
      "l"
      "la"
      "ll"
      "lla"
      "lt"
      "lg"
      "pwd"
    ];
    historySize = 100000;
    historyFileSize = 200000;

    shellOptions = [
      "histappend"
      "checkwinsize"
      "extglob"
      "globstar"
      "cmdhist"
      "checkjobs"
      "lithist"
    ];
  };
}
