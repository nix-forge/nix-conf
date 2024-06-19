{ self, ... }:
{
  imports = [ self.nixOSModules.hardware.cpu.amd ];

  hardware.cpu.amd.enable = true;
}
