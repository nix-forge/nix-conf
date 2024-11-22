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
}
