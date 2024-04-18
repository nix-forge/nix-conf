{
  self,
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    inputs.hyprland-nix.homeManagerModules.hyprland
    ./config.nix
    ./windowrules.nix
    ./keybinds.nix
  ];

  home.packages = [
    # xwayland perm for pkexec
    pkgs.xorg.xhost
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    package = inputs.hyprland-git.packages.${pkgs.system}.hyprland;
    reloadConfig = true;
    systemdIntegration = true;
    recommendedEnvironment = true;
    xwayland.enable = true;

    config.exec_once = [
      # polkit agent, raises to root access with gui
      # "${pkgs.gnome.gnome-keyring}/bin/gnome-keyring-daemon --start --components=pkcs11,secrets,ssh"
      # allow apps with risen perms after agent to connect to local xwayland
      "${lib.getExe pkgs.xorg.xhost} +local:"
    ];
  };
}
