_: {
  # Nixpkgs installs its sandbox-preserving Wootility wrapper and grants
  # Wooting HID access only to the active local session through uaccess.
  hardware.wooting.enable = true;

  # Pulsar's Linux Web Driver (Bibimbap) requires a uaccess ACL on the HID
  # device. The product ID differs by wired/wireless/firmware mode, so scope
  # the rule to Pulsar's USB vendor ID rather than granting generic hidraw
  # access. `uaccess` grants access only to the active local session.
  services.udev.extraRules = builtins.readFile ./70-pulsar.rules;
}
