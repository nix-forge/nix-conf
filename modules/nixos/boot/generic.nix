{ lib, ... }: {
  # NixOS 26.11 requires the systemd initrd. Older pins still need an explicit
  # baseline before shared modules can rely on declarative initrd units.
  boot.initrd.systemd = {
    # Do not make an unauthenticated initrd shell a fallback boot path.
    # Hosts needing an emergency shell or a hashed recovery password opt in
    # from their local boot configuration.
    emergencyAccess = lib.mkDefault false;
  }
  // lib.optionalAttrs (lib.versionOlder (lib.versions.majorMinor lib.version) "26.11") {
    enable = lib.mkDefault true;
  };
}
