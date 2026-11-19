{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.home-manager.users.ianmh.programs.voiceDictation.enable {
    boot.kernelModules = [ "uinput" ];
    # Handy's native push-to-talk backend needs evdev and uinput to consume the
    # shortcut without inserting a space. Grant the active local seat access,
    # rather than permanent input-group membership. Run before 73-seat-late.
    services.udev.packages = [
      (pkgs.writeTextDir "lib/udev/rules.d/70-handy-input.rules" ''
        KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess"
        SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", TAG+="uaccess"
      '')
    ];
  };
}
