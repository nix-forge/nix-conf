{
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";

    memtest86.enable = true;
  };
}
