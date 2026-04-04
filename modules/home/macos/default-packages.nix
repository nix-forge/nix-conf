{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  lowerPriority = pkg: lib.setPrio ((pkg.meta.priority or lib.meta.defaultPriority) + 3) pkg;

  defaultPackageNames = [
    "perl"
    "rsync"
    "strace"
  ];

  resolvePackage =
    name:
    if !builtins.hasAttr name pkgs then
      [ ]
    else
      let
        pkg = pkgs.${name};
      in
      lib.optional (lib.meta.availableOn pkgs.stdenv.hostPlatform pkg) (lowerPriority pkg);

  defaultPackages = lib.concatMap resolvePackage defaultPackageNames;
in
{
  home.packages = lib.mkIf isDarwin defaultPackages;
}
