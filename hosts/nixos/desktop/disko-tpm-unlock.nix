{ config, lib, ... }: {
  # This is a post-provisioning module, intentionally separate from Disko. It
  # becomes safe only after the LUKS recovery key, passphrase boot path, and
  # Lanzaboote Secure Boot path have each been tested at the physical console.
  boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = [ "tpm2-device=auto" ];

  assertions = [
    {
      assertion = config.boot.initrd.systemd.enable;
      message = "TPM2 LUKS unlock requires the systemd initrd.";
    }
    {
      assertion = config.security.tpm2.enable;
      message = "TPM2 LUKS unlock requires security.tpm2.enable.";
    }
    {
      assertion = config.security.secureBootLanzaboote.enable;
      message = "Import disko-tpm-unlock.nix only after the attended Lanzaboote Secure Boot rollout.";
    }
    {
      assertion = config.security.secureBootLanzaboote.measuredBoot.enable;
      message = "TPM2 LUKS unlock must use Lanzaboote's tested measured-boot policy, not a static PCR binding.";
    }
    {
      assertion = lib.hasAttrByPath [ "cryptroot" ] config.boot.initrd.luks.devices;
      message = "TPM2 LUKS unlock expects the Disko cryptroot mapping.";
    }
  ];
}
