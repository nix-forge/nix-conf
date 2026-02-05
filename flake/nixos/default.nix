{ myLib, config, ... }:
{
  flake.modules.nixos = myLib.dir.importFlatWithDirs ../../modules/nixos { sep = "-"; };
  flake.nixosModules = config.flake.modules.nixos;
}
