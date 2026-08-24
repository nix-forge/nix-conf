{ lib, ... }: {
  # NixOS uses a systemd-based initrd by default. State the baseline
  # explicitly so shared modules can rely on its declarative units without
  # carrying any machine-specific storage drivers or unlock policy.
  boot.initrd.systemd = {
    enable = lib.mkDefault true;

    # Do not make an unauthenticated initrd shell a fallback boot path.
    # Hosts needing an emergency shell or a hashed recovery password opt in
    # from their local boot configuration.
    emergencyAccess = lib.mkDefault false;
  };
}
