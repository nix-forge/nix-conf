{ myLib, ... }:
{
  flake.nixosModules = myLib.dir.importFlatWithDirs ../../nixosModules { sep = "-"; };
}
