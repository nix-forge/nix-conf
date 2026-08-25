{ pkgs, ... }: {
  # Firmware Secure Boot is presently disabled. Keep Lanzaboote staged but
  # inactive until the recovery procedure in docs/secure-boot-lanzaboote.md
  # has been completed on the physical console. Changing this to true before
  # keys exist intentionally fails the activation rather than risking an
  # unsigned or unbootable ESP.
  security.secureBootLanzaboote = {
    enable = false;
    pkiBundle = "/var/lib/sbctl";

    # The desktop's 1 GiB ESP, signed generations, and eventual pcrlock
    # support favor a bounded rollback set. Three failed attempts is enough
    # to recover from a bad generation without masking a transient failure.
    configurationLimit = 8;
    bootCountingInitialTries = 3;

    # Measured Boot is deliberately deferred. The present Btrfs root is not
    # LUKS2-encrypted, so TPM sealing would not protect its contents. Once a
    # LUKS2 migration has a tested recovery passphrase, enable this with the
    # selected PCR 4 + 7 policy and an attended TPM2-with-PIN enrollment.
    measuredBoot = {
      enable = false;
      pcrs = [
        4
        7
      ];
    };
  };

  # Available now for preflight, signing-key creation, verification, and
  # recovery diagnostics. Its key bundle stays root-owned at /var/lib/sbctl.
  environment.systemPackages = [ pkgs.sbctl ];
}
