{ self, ... }:
{
  imports = [ self.nixOSModules.hardware.cpu.amd ];

  hardware.cpu.amd = {
    enable = true;
    iommu.enable = true;
    kvm = {
      enable = true;
      nestedVirtualization = true;
    };
  };
}
