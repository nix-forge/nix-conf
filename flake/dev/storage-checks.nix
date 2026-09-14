{ inputs, self, ... }: {
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    let
      desktop = self.nixosConfigurations.desktop;
      migrated =
        (desktop.extendModules { modules = [ { hardware.storage.encryptedRoot.enable = true; } ]; }).config;
      diskSwap = builtins.head migrated.swapDevices;
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        application-recovery = import ../../tests/recovery/application-recovery.nix { inherit pkgs; };
        desktop-storage-install = import ../../tests/storage/install.nix {
          inherit pkgs;
          diskoLib = import "${inputs.disko}/lib" {
            inherit lib;
            makeTest = import "${inputs.nixpkgs}/nixos/tests/make-test-python.nix";
            eval-config = import "${inputs.nixpkgs}/nixos/lib/eval-config.nix";
            qemu-common = import "${inputs.nixpkgs}/nixos/lib/qemu-common.nix";
          };
        };
        desktop-storage-contracts =
          assert lib.all (a: a.assertion) migrated.assertions;
          assert !(desktop.config.services.greetd.settings ? initial_session);
          assert !(migrated.services.greetd.settings ? initial_session);
          assert diskSwap.randomEncryption.enable;
          assert diskSwap.device == "/dev/disk/by-partlabel/NIXOS-SWAP";
          assert builtins.length migrated.swapDevices == 1;
          assert migrated.fileSystems."/".device == "/dev/mapper/cryptroot";
          assert migrated.fileSystems."/mnt/games".device == "/dev/mapper/cryptdata";
          assert !(migrated.boot.initrd.luks.devices ? cryptdata);
          assert migrated.boot.resumeDevice == "";
          assert !migrated.virtualisation.libvirtWorkstation.storage.nocow;
          assert migrated.fileSystems."/home/ianmh/.cache".device == "/dev/mapper/cryptroot";
          assert
            migrated.systemd.services.btrfs-scrub-srv-data.unitConfig.ConditionPathIsMountPoint == "/srv/data";
          assert
            desktop.config.systemd.services.btrfs-scrub-mnt-games.unitConfig.ConditionPathIsMountPoint
            == "/mnt/games";
          assert migrated.services.snapper.configs.home.FREE_LIMIT == 0.2;
          assert migrated.services.snapper.configs.home.TIMELINE_LIMIT_HOURLY == "0-24";
          assert migrated.systemd.timers.desktop-snapshot-home-cleanup.timerConfig.OnCalendar == "hourly";
          assert
            builtins.attrNames migrated.services.snapper.configs == [
              "data"
              "home"
              "work"
            ];
          assert migrated.services.restic.backups == { };
          pkgs.runCommand "desktop-storage-contracts"
            {
              report = builtins.unsafeDiscardStringContext migrated.system.build.toplevel.drvPath;
              nativeBuildInputs = [ pkgs.libxml2 ];
            }
            ''
              test "$(xmllint --xpath 'string(/pool/features/cow/@state)' ${builtins.elemAt migrated.systemd.services.libvirt-workstation-setup.restartTriggers 1})" = yes
              printf '%s\n' "$report" > "$out"
            '';
      };
    };
}
