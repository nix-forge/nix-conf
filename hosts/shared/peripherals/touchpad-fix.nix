{ pkgs, ... }:
{
  # workaround for broken libinput gestures and two-finger scrolling.
  # <https://askubuntu.com/a/828920>
  powerManagement.powerDownCommands = ''
    ${pkgs.kmod}/bin/modprobe -r psmouse
  '';
  powerManagement.resumeCommands = ''
    ${pkgs.kmod}/bin/modprobe psmouse
  '';
}
