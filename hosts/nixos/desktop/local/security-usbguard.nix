{ lib, ... }: {
  security.usbguardBaseline.enable = true;

  services.usbguard = {
    # This immutable policy was generated on 2026-08-24 with:
    #   usbguard generate-policy -p -H
    # on this desktop, then reviewed. Fixed devices are pinned to their full
    # descriptor hash, parent topology, and physical port. The Wooting and
    # Pulsar rules intentionally omit topology so those exact reviewed devices
    # work both directly and through the monitor KVM. Regenerate and review the
    # policy after a motherboard/peripheral firmware change or hardware move;
    # do not add broad vendor-ID allow rules.
    # The Pulsar X2 V2 Mini has separate identities for its wireless receiver
    # (3554:f508) and wired mode (3554:f507). The wired descriptor hash was
    # reviewed from this desktop's USBGuard audit log on 2026-09-06.
    # Both YubiKeys were configured with USB OTP disabled on 2026-09-09.
    # Their FIDO+CCID descriptor hash was reviewed from USBGuard insertion
    # events after that change. Both present the same hash and no USB serial,
    # so this rule matches identical descriptors, not a unique physical key.
    # It omits topology to permit moving between USB ports. Changes to enabled
    # USB interfaces require another descriptor review.
    # The WD Elements backup drive is pinned to its reviewed descriptor hash
    # and mass-storage interface. Topology is omitted so this portable backup
    # device can move between ports; other mass-storage devices stay blocked.
    # The Brio 101 webcam is pinned to its reviewed descriptor hash and hub
    # port and video/audio interfaces. This trusts the hardware without adding
    # a privileged enable step before each call; application access is separate.
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
