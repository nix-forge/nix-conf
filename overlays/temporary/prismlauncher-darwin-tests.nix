_: {
  reason = "The native watch integration test assumes a macOS capability denied by the sandbox.";
  upstream = "https://github.com/PrismLauncher/PrismLauncher";
  removal = "Upstream checks the native watch prerequisite before running the integration case.";
  reviewedRevision = "8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/prismlauncher-watch-test-capability.patch ];
    });
}
