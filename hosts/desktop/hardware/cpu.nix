{ self, ... }:
{
  imports = [
    self.nixOSModules.hardware.cpu.amd
  ];

  hardware.cpu.amd = {
    enable = true;
    iommu.enable = true;
    kvm = {
      enable = true;
      nestedVirtualization = true;
    };
  };

  # Set cpu model id for ucodenix flake
  services.ucodenix.cpuModelId = "00A60F12";
}
