{ inputs, self, ... }: {
  perSystem =
    { pkgs, ... }:
    let
      selected = pkgs.extend (import ../../overlays { inherit inputs; });
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
      desktop = self.nixosConfigurations.desktop.config;
    in
    {
      checks = {
        temporary-package-fixes =
          assert desktop.nix.package.drvPath == self.nixosConfigurations.desktop.pkgs.nix.drvPath;
          assert pkgs.lib.any (
            command:
            pkgs.lib.hasInfix "--nix-bin ${builtins.unsafeDiscardStringContext desktop.nix.package.outPath}/bin" command
          ) desktop.systemd.services.nix-daemon.serviceConfig.ExecStart;
          builtins.deepSeq results (
            pkgs.runCommand "temporary-package-fixes" { } ''
              touch "$out"
            ''
          );
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        sentry-crashpad-lock = selected.nix.tests.crashpad-lock;
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
                ${selected.nix.tests.crashpad-lock.src} \
                ${../../overlays/temporary/patches/apply-crashpad-lock.sh} \
                ${../../overlays/temporary/patches/sentry-crashpad-lock.patch}
              touch "$out"
            '';
      };
    };
}
