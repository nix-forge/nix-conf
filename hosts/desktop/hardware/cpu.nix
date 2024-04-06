{ self, ... }:
{
  imports = [ self.nixosModules.hardware.cpu.amd ];

  hardware.cpu.amd.enable = true;
}
