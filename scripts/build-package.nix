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
assert builtins.elem buildSystem linuxSystems;
assert builtins.elem hostSystem linuxSystems;
builtins.getAttr package packages
