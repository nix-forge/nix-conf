_: {
  reason = "APFS extraction creates a quarantine alternate-stream file inside LinearMouse's signed login helper, invalidating its sealed resources.";
  upstream = "https://github.com/NixOS/nixpkgs/blob/b3cff76391a4867236cc135b69a928d873b9f6d0/pkgs/by-name/li/linearmouse/package.nix";
  removal = "The official recipe excludes APFS alternate streams during extraction and passes Apple's deep strict signature verification without this override.";
  reviewedRevision = "b3cff76391a4867236cc135b69a928d873b9f6d0";
  inputPath = [ "nixpkgs-apps" ];
  packageName = "linearmouse";
  affectedVersions = {
    from = "0.12.0";
    until = "0.12.1";
  };
  apply =
    package:
    assert package.unpackCmd == "7zz x $curSrc";
    package.overrideAttrs { unpackCmd = "7zz x -sns- $curSrc"; };
}
