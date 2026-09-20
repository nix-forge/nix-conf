{ lib, ... }: {
  security.usbguardBaseline.enable = true;

  services.usbguard = {
    # The rules identify each trusted USB function. Fixed controllers and
    # onboard devices retain topology checks; movable peripherals and the
    # monitor KVM use device ID, descriptor hash, and exact interface sets so
    # they work through a different hub or port. The YubiKey rule covers both
    # previously tested 5C keys with USB OTP disabled. Since neither presents
    # a USB serial, an identical descriptor can also match that rule.
    # USB descriptors can be spoofed; review an unexpected identity or firmware
    # change before allowing it. The Samsung Flash Drive FIT remains blocked.
    # Keep the policy declarative and deny by default.
    rules = builtins.readFile ./security-usbguard.rules;

  };

  # Select this systemd-boot specialisation if a changed descriptor or local
  # policy prevents a necessary HID device from working. It removes only
  # USBGuard; the normal boot entry remains the secure default.
  specialisation.usbguard-recovery.configuration = {
    security.usbguardBaseline.enable = lib.mkForce false;
    services.usbguard.enable = lib.mkForce false;
  };
}
