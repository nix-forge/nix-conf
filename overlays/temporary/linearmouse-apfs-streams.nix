_: {
  reason = "APFS extraction creates a quarantine alternate-stream file inside LinearMouse's signed login helper, invalidating its sealed resources.";
  upstream = "https://github.com/NixOS/nixpkgs/blob/b3cff76391a4867236cc135b69a928d873b9f6d0/pkgs/by-name/li/linearmouse/package.nix";
  removal = "The official recipe excludes APFS alternate streams during extraction and passes Apple's deep strict signature verification without this override.";
  reviewedRevision = "04906337b6d53e8bb0eaf0470ae9f070a4d4eb55";
  inputPath = [ "nixpkgs" ];
  packageName = "linearmouse";
  affectedVersions = {
    from = "0.12.0";
    until = "0.12.1";
  };
  apply =
    package:
    if package.unpackCmd != "7zz x $curSrc" then
      throw "Invalid production input in linearmouse-apfs-streams.nix"
    else
      package.overrideAttrs { unpackCmd = "7zz x -sns- $curSrc"; };
}
