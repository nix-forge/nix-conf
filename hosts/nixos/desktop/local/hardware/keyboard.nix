{ pkgs, ... }: {
  # Match the supported digital work keyboard, not every evdev input device.
  # Rules must precede 73-seat-late.rules for logind's active-seat ACL handling.
  # No permanent input-group membership is granted to the login user.
  boot.kernelModules = [ "uinput" ];
  services.udev.packages = [
    (pkgs.writeTextDir "lib/udev/rules.d/70-work-keyboard.rules" ''
      SUBSYSTEM=="input", KERNEL=="event*", ATTRS{idVendor}=="31e3", ATTRS{idProduct}=="1400", ENV{ID_INPUT_KEYBOARD}=="1", TAG+="uaccess"
      SUBSYSTEM=="misc", KERNEL=="uinput", TAG+="uaccess"
    '')
  ];
}
