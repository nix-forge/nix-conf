{ lib, pkgs, ... }:
let
  fd = lib.getExe pkgs.fd;
  fdOptions = "--hidden --exclude .git --exclude .direnv --exclude node_modules --exclude result --exclude dist --exclude build";
in
{
  home.packages = [ pkgs.fd ];

  programs.fzf = {
    enable = true;

    # Atuin owns Ctrl-R. fd skips .git so the file and directory widgets stay
    # responsive even from large repositories.
    defaultCommand = "${fd} --type f ${fdOptions}";
    fileWidget.command = "${fd} --type f ${fdOptions}";
    changeDirWidget.command = "${fd} --type d ${fdOptions}";
    historyWidget.command = "";
    defaultOptions = [
      "--height=40%"
      "--layout=reverse"
      "--border"
      "--cycle"
    ];
  };
}
