_: {
  reason = "The native watch integration test assumes a macOS capability denied by the sandbox.";
  upstream = "https://github.com/PrismLauncher/PrismLauncher/pull/6165";
  removal = "Upstream checks the native watch prerequisite before running the integration case.";
  reviewedRevision = "1d060086d60cb76a40cf37109f979d88a5bd6396";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/prismlauncher-watch-test-capability.patch ];
    });
}
