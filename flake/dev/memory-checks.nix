{ self, ... }: {
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        codex-resources = (import ../../tests/python-check.nix { inherit pkgs; }) {
          name = "codex-resource-behavior";
          files = [
            ../../homes/desktop/local/codex-resources/scripts
            ../../homes/desktop/local/browsers/scripts/zen-session.sh.in
            ../../tests/codex/test_resources.py
            ../../tests/codex/fixtures/resource_app.py
            ../../tests/codex/fixtures/resource_notify.py
            ../../tests/codex/fixtures/resource_systemctl.py
          ];
          testPaths = [ "tests/codex/test_resources.py" ];
        };
        desktop-workload = import ../../tests/nix/desktop-workload.nix {
          inherit pkgs;
          desktopConfig = self.nixosConfigurations.desktop.config;
        };
        desktop-swap-boot = import ../../tests/nix/desktop-swap-boot.nix {
          inherit pkgs;
          desktopConfig = self.nixosConfigurations.desktop.config;
        };
        desktop-iocost = import ../../tests/nix/desktop-iocost.nix { inherit pkgs; };
        desktop-memory-policy =
          let
            config = self.nixosConfigurations.desktop.config;
            policy = config.system.build.desktopMemoryPolicy;
            home = builtins.head (
              builtins.filter (home: home.home.activation ? preserveConfigurationConflicts) (
                builtins.attrValues config.home-manager.users
              )
            );
          in
          assert import ../../tests/nix/backup-exclusions.nix { inherit lib; };
          pkgs.runCommand "desktop-memory-policy-check"
            {
              nativeBuildInputs = [
                pkgs.gnugrep
                pkgs.jq
                pkgs.shellcheck
                pkgs.python3
              ];
            }
            (
              (import ../../lib/templates/text.nix) ./scripts/desktop-memory-policy-check.sh {
                inherit policy;
                backupCleanupFixture = ../../tests/nix/scripts/check_backup_cleanup.py;
                preserveConfigurationFixture = pkgs.writeText "fixture-preserve-configuration.sh" (
                  builtins.replaceStrings [ home.home.homeDirectory ] [ "/build/fixture-home" ]
                    home.home.activation.preserveConfigurationConflicts.data
                );
              }
            );
      };
    };
}
