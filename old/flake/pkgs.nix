{ self, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      legacyPackages = lib.pipe (self.lib.cust.files.importDirRec ./../pkgs [ ]) [
        (
          packages:
          lib.makeScope pkgs.newScope (
            self:
            (lib.mapAttrs' (
              folderName: pkg:
              lib.nameValuePair (lib.strings.replaceStrings [ "_" ] [ "-" ] folderName) (self.callPackage pkg { })
            ))
              packages
          )
        )
      ];
      # Flatten one level of nested attribute sets (directories whose default.nix
      # returns an attrset of derivations, e.g., vscode-extensions) so their
      # members become top-level packages. For nested sets, create prefixed names
      # like "<parent>-<child>" (e.g., vscode-extensions-copilot). Do not export
      # unprefixed child names to avoid duplicates in `nix flake show`. Then
      # filter to derivations available on the current host and not marked broken.
      flattenedPackages = builtins.foldl' (
        acc: name:
        let
          value = legacyPackages.${name};
        in
        if lib.isDerivation value then
          acc // { ${name} = value; }
        else if lib.isAttrs value then
          let
            childDrvs = lib.filterAttrs (_: v: lib.isDerivation v) value;
            prefixedChildDrvs = builtins.listToAttrs (
              map (childName: {
                name = "${name}-${childName}";
                value = childDrvs.${childName};
              }) (builtins.attrNames childDrvs)
            );
          in
          acc // prefixedChildDrvs
        else
          acc
      ) { } (builtins.attrNames legacyPackages);

      packages = lib.filterAttrs (
        _: pkg:
        let
          isDerivation = lib.isDerivation pkg;
          availableOnHost = lib.meta.availableOn pkgs.stdenv.hostPlatform pkg;
          isBroken = pkg.meta.broken or false;
        in
        isDerivation && !isBroken && availableOnHost
      ) flattenedPackages;
    in
    {
      inherit legacyPackages packages;
    };
}
