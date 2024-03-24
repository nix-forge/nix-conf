{
  boot = {
    initrd.systemd.strip = false;
    initrd.systemd.enable = true;

    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };

      grub = {
        enable = true;
        efiSupport = true;
        device = "nodev";
        configurationLimit = 10;
      };
    };
  };
}
