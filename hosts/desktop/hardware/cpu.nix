{ self, ... }:
{
  imports = [ self.nixosModules.hardware-cpu-amd ];

  hardware.cpu.amd = {
    enable = true;
    iommu.enable = true;
    kvm = {
      enable = true;
      nestedVirtualization = true;
    };
  };

  # Config for ucodenix
  # Set cpu model id for ucodenix flake
  services.ucodenix.cpuModelId = "00A60F12";
  boot.kernelParams = [ "microcode.amd_sha_check=off" ];
}
