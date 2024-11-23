{ self, ... }:
{
  imports = [ self.nixOSModules.hardware.cpu.intel ];

  hardware.cpu.intel = {
    enable = true;
    iommu.enable = true;
    kvm = {
      enable = true;
      nestedVirtualization = true;
    };
  };

  services.thermald.enable = true;

  services.auto-cpufreq = {
    enable = true;
    settings = {
      charger = {
        governor = "performance";

        energy_performance_preference = "performance"; # specific to laptop
        platform_profile = "performance"; # specific to laptop

        turbo = "auto";
      };
      battery = {
        governor = "powersave";

        energy_performance_preference = "power"; # specific to laptop
        platform_profile = "quiet"; # specific to laptop

        turbo = "never";
      };
    };
  };
}
