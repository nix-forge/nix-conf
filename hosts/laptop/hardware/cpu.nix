{ self, ... }:
{
  imports = [ self.nixosModules.hardware.cpu.intel ];

  hardware.cpu.intel.enable = true;
}
