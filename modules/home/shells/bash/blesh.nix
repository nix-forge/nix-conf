{
  pkgs,
  lib,
  config,
  ...
}:
{
  home.packages = [ pkgs.blesh ];

  programs.bash = {
    bashrcExtra = lib.mkBefore ''
      [[ $- == *i* ]] && source "${pkgs.blesh}/share/blesh/ble.sh" --attach=none
    '';

    initExtra = lib.mkMerge [
      (lib.mkIf config.programs.carapace.enable ''
        source <(${lib.getExe config.programs.carapace.package} _carapace bash-ble)
      '')
      (lib.mkOrder 2000 ''
        [[ ''${BLE_VERSION-} ]] && ble-attach
      '')
    ];
  };

  programs.carapace.enableBashIntegration = lib.mkIf config.programs.carapace.enable (
    lib.mkForce false # Enabling breaks ble
  );
}
