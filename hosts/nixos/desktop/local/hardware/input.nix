{ pkgs, ... }: {
  # The NixOS-packaged Wootility app and its vendor-maintained udev rules give
  # the logged-in user WebHID/hidraw access to a Wooting 80HE without broad
  # membership in the `input` group.
  environment.systemPackages = [ pkgs.wootility ];
  services.udev.packages = [ pkgs.wooting-udev-rules ];

  # Pulsar's Linux Web Driver (Bibimbap) requires a uaccess ACL on the HID
  # device. The product ID differs by wired/wireless/firmware mode, so scope
  # the rule to Pulsar's USB vendor ID rather than granting generic hidraw
  # access. `uaccess` grants access only to the active local session.
  services.udev.extraRules = builtins.readFile ./70-pulsar.rules;
}
