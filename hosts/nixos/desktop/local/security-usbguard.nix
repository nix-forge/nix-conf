{ lib, ... }: {
  security.usbguardBaseline.enable = true;

  services.usbguard = {
    # This immutable policy was generated on 2026-08-24 with:
    #   usbguard generate-policy -p -H
    # on this desktop, then reviewed. Each permanent device is pinned to its
    # full descriptor hash, parent topology, and physical port. Regenerate and
    # review it after a motherboard/peripheral firmware change or hardware move;
    # do not add broad vendor-ID allow rules.
    #
    # The currently attached Samsung Flash Drive FIT (090c:1000) is deliberately
    # absent. Removable mass storage is blocked by default. If it becomes a
    # trusted, permanently attached recovery device, add a reviewed hash-and-
    # port rule here.
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
