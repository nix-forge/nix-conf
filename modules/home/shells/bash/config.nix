{ lib, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  home.packages = [ pkgs.bash-language-server ];
  home.sessionVariables.SHELL = lib.getExe pkgs.bashInteractive;

  programs.bash = {
    enable = true;
    package = pkgs.bashInteractive;
    enableCompletion = true;
    enableVteIntegration = lib.mkIf isLinux true;

    historyControl = [ "ignoreboth" ];
    historyIgnore = [
      "cd"
      "cd *"
      "clear"
      "exit"
      "history"
      "history *"
      "ls"
      "ls *"
      "l"
      "l *"
      "la"
      "la *"
      "ll"
      "ll *"
      "lla"
      "lla *"
      "lt"
      "lt *"
      "lg"
      "lg *"
      "pwd"
    ];
    # Atuin owns durable, searchable history. Keep enough native history for a
    # useful offline fallback without repeatedly scanning a six-figure list.
    historySize = 20000;
    historyFileSize = 40000;

    shellOptions = [
      "histappend"
      "autocd"
      "cdspell"
      "checkwinsize"
      "dirspell"
      "extglob"
      "globstar"
      "cmdhist"
      "checkjobs"
      "histverify"
      "lithist"
    ];
  };

  # ble.sh reads the Readline editing mode at startup and replaces Readline for
  # normal interactive use. These settings also give --norc and no-ble rescue
  # shells the same predictable vi-oriented behavior.
  programs.readline = {
    enable = true;
    variables = {
      bell-style = "none";
      colored-completion-prefix = true;
      colored-stats = true;
      completion-ignore-case = true;
      completion-map-case = true;
      editing-mode = "vi";
      enable-bracketed-paste = true;
      keymap = "vi-insertion";
      mark-symlinked-directories = true;
      menu-complete-display-prefix = true;
      revert-all-at-newline = true;
      show-all-if-ambiguous = true;
      skip-completed-text = true;
      visible-stats = true;
    };
  };
}
