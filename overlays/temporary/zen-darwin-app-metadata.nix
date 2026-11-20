_: {
  reason = "Zen exposes applicationName but omits the standard mainDarwinApp metadata.";
  upstream = "https://github.com/0xc000022070/zen-browser-flake/blob/9107affa07d1213f0e733ba62235bf23453cfb98/package.nix";
  removal = "Zen declares mainDarwinApp from applicationName on Darwin.";
  reviewedRevision = "2cc6b81e90ea910e6ddbbc0f4c665b4545060a75";
  inputPath = [ "zen-browser" ];
  apply =
    package:
    package.overrideAttrs (old: {
      meta = {
        mainDarwinApp = "${package.applicationName}.app";
      }
      // (old.meta or { });
    });
}
