_: {
  perSystem =
    { myLib, pkgs, ... }:
    let
      writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
      runtime = import ./runtime-packages.nix { inherit pkgs; };
    in
    {
      packages = {
        seed-ci-cache = writeShellApplication {
          name = "seed-ci-cache";
          text = ''
            case "$DEV_SHELL" in
            ciRust | ci) ;;
            *)
              echo 'Only reviewed static tool shells can seed this cache' >&2
              exit 2
              ;;
            esac
            # The profile retains exact tool dependencies through the cache post-action's GC.
            # Do not seed application, host, private or redistribution-restricted closures.
            nix print-dev-env ".#$DEV_SHELL" --profile "$RUNNER_TEMP/cache-environment" \
              >"$RUNNER_TEMP/cache-environment.sh"
            {
              printf '### Retained %s closure\n\n' "$CACHE_SCOPE"
              nix path-info --closure-size "$RUNNER_TEMP/cache-environment"
              echo 'NAR closure size is distinct from compressed cache size.'
              echo 'The cache post-action records the actual save and transfer result.'
            } >>"$GITHUB_STEP_SUMMARY"
          '';
        };
        native-package-selection = runtime.nativePackageSelection;
        remote-realise = runtime.remoteRealise;
        mac-source = runtime.macSource;
        homelab-credentials = runtime.homelabCredentials;
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        build-linux-package = runtime.buildLinuxPackage;
      };
    };
}
