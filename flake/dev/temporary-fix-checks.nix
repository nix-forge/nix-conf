{ inputs, self, ... }: {
  perSystem =
    { pkgs, ... }:
    let
      determinatePackage = import ../../tests/nix/determinate-module.nix { inherit pkgs inputs; };
      # Evaluation covers all supported platforms without building foreign
      # packages or moving the desktop closure to another builder.
      results = builtins.listToAttrs (
        map
          (system: {
            name = system;
            value = import ../../tests/nix/temporary-fixes.nix {
              inherit inputs;
              pkgs = import inputs.nixpkgs {
                inherit system;
                config.allowUnfree = true;
              };
            };
          })
          [
            "x86_64-linux"
            "aarch64-linux"
            "aarch64-darwin"
          ]
      );
    in
    {
      checks = {
        temporary-package-fixes = builtins.deepSeq results (
          pkgs.runCommand "temporary-package-fixes" { } ''
            touch "$out"
          ''
        );
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        swift-wrapper-hardening = self.darwinConfigurations.macbook-pro-m4.pkgs.swift.tests.hardening;
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        sentry-crashpad-lock = determinatePackage.tests.crashpad-lock;
        sentry-crashpad-lock-lifecycle =
          pkgs.runCommand "sentry-crashpad-lock-lifecycle"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.patch
                pkgs.python3
              ];
            }
            ''
              python3 ${../../overlays/temporary/tests/crashpad-lock-lifecycle.py} \
                ${determinatePackage.tests.crashpad-lock.src} \
                ${../../overlays/temporary/patches/apply-crashpad-lock.sh} \
                ${../../overlays/temporary/patches/sentry-crashpad-lock.patch}
              touch "$out"
            '';
      };
    };
}
