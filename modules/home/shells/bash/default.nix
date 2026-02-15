{ lib, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  home.shell.enableBashIntegration = true;
  programs.bash = {
    enable = true;
    enableCompletion = true;
    enableVteIntegration = lib.mkIf isLinux true;

    historyControl = [
      "ignoreboth"
      "erasedups"
    ];
    historyIgnore = [
      "exit"
      "clear"
    ];
    historySize = 100000;
    historyFileSize = 200000;

    shellOptions = [
      "histappend"
      "checkwinsize"
      "extglob"
      "globstar"
      "cmdhist"
    ];

    initExtra = lib.mkMerge [
      (lib.mkOrder 500 ''
        source -- "${pkgs.blesh}/share/blesh/ble.sh" --attach=none
      '')

      (lib.mkOrder 2000 ''
        [[ ! ''${BLE_VERSION-} ]] || ble-attach
      '')
    ];
  };
}
