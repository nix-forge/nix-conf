{
  boot = {
    loader = {
      efi = {
        canTouchEfiVariables = true;
      };

      grub = {
        enable = true;
        efiSupport = true;
        device = "nodev";
        configurationLimit = 15; # default is 100
      };
    };
  };
}
