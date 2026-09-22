_: {
  reason = "The native watch integration test assumes a macOS capability denied by the sandbox.";
  upstream = "https://github.com/PrismLauncher/PrismLauncher";
  removal = "Upstream checks the native watch prerequisite before running the integration case.";
  reviewedRevision = "44a91898084f46797b5fac650c7e8c9ac38c43d4";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/prismlauncher-watch-test-capability.patch ];
    });
}
