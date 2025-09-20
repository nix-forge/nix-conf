{ self, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      legacyPackages = lib.pipe (self.lib.cust.files.importDirRec ./../pkgs [ ]) [
        (
          packages:
          lib.makeScope pkgs.newScope (
            self: (builtins.mapAttrs (_folderName: pkg: self.callPackage pkg { })) packages
          )
        )
      ];
      packages = lib.filterAttrs (
        _: pkg:
        let
          isDerivation = lib.isDerivation pkg;
          availableOnHost = lib.meta.availableOn pkgs.stdenv.hostPlatform pkg;
          isBroken = pkg.meta.broken or false;
        in
        isDerivation && !isBroken && availableOnHost
      ) legacyPackages;
    in
    {
      inherit legacyPackages packages;
    };
}
