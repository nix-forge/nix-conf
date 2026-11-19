{
  repository,
  buildSystem,
  hostSystem,
  package,
}:
let
  linuxSystems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
  source = builtins.getFlake repository;
  packages = source.lib.packagesFor { inherit buildSystem hostSystem; };
in
if !(builtins.elem buildSystem linuxSystems) then
  throw "Invalid production input in build-package.nix"
else if !(builtins.elem hostSystem linuxSystems) then
  throw "Invalid production input in build-package.nix"
else
  builtins.getAttr package packages
