{
  boot.initrd.systemd = {
    enable = true;
    tpm2.enable = true;
  };

  boot.initrd.luks.devices.cryptroot = {
    device = "/dev/disk/by-partlabel/cryptroot";
    allowDiscards = true;
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };
}
