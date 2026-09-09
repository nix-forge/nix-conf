_: {
  reason = "The native watch integration test assumes a macOS capability denied by the sandbox.";
  upstream = "https://github.com/PrismLauncher/PrismLauncher";
  removal = "Upstream checks the native watch prerequisite before running the integration case.";
  reviewedRevision = "c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/prismlauncher-watch-test-capability.patch ];
    });
}
