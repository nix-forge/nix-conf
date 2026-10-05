_: {
  reason = "The native watch integration test assumes a macOS capability denied by the sandbox.";
  upstream = "https://github.com/PrismLauncher/PrismLauncher";
  removal = "Upstream checks the native watch prerequisite before running the integration case.";
  reviewedRevision = "c59305bab2065cfecc4944690d9eedbb56f3a9fa";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/prismlauncher-watch-test-capability.patch ];
    });
}
