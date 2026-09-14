{
  inputs,
  myLib,
  self,
  ...
}:
{
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
      currentCrypttab =
        pkgs.writeText "desktop-current-crypttab"
          desktop.config.environment.etc."crypttab".text;
      migratedCrypttab =
        pkgs.writeText "desktop-migrated-crypttab"
          migrated.environment.etc."crypttab".text;
      currentFstab = desktop.config.environment.etc."fstab".source;
      migratedFstab = migrated.environment.etc."fstab".source;
      homelabScrubUnit = desktop.config.systemd.units."btrfs-scrub-mnt-homelab.service".unit;
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        application-recovery = import ../../tests/recovery/application-recovery.nix { inherit pkgs; };
        desktop-storage-install = import ../../tests/storage/install.nix {
          inherit pkgs myLib;
          diskoLib = import "${inputs.disko}/lib" {
            inherit lib;
            makeTest = import "${inputs.nixpkgs}/nixos/tests/make-test-python.nix";
            eval-config = import "${inputs.nixpkgs}/nixos/lib/eval-config.nix";
            qemu-common = import "${inputs.nixpkgs}/nixos/lib/qemu-common.nix";
          };
        };
        desktop-storage-generated-artifacts =
          pkgs.runCommand "desktop-storage-generated-artifacts"
            {
              nativeBuildInputs = [
                pkgs.coreutils
                pkgs.gnugrep
              ];
            }
            ''
              check_homelab_mount() {
                grep -Eq '^/dev/mapper/homelab[[:space:]]+/mnt/homelab[[:space:]]+btrfs[[:space:]]+.*subvol=@homelab' "$1"
                grep -Eq '^/dev/mapper/homelab[[:space:]]+/mnt/homelab[[:space:]]+btrfs[[:space:]]+.*nodiscard' "$1"
                grep -Eq '^/dev/mapper/homelab[[:space:]]+/mnt/homelab[[:space:]]+btrfs[[:space:]]+.*x-systemd.automount' "$1"
              }
              check_homelab_mount ${currentFstab}
              check_homelab_mount ${migratedFstab}
              grep -Fqx 'homelab /dev/disk/by-uuid/fd63a64b-e779-4557-bc98-cff841faf19b none luks,noauto,nofail,x-systemd.device-timeout=10s' ${currentCrypttab}
              grep -Fqx 'homelab /dev/disk/by-uuid/fd63a64b-e779-4557-bc98-cff841faf19b /var/lib/desktop-storage/keys/homelab.key luks,noauto,nofail,x-systemd.device-timeout=10s,headless' ${migratedCrypttab}
              grep -Fqx 'ConditionPathIsMountPoint=/mnt/homelab' ${homelabScrubUnit}/btrfs-scrub-mnt-homelab.service
              grep -Fqx 'IOSchedulingClass=idle' ${homelabScrubUnit}/btrfs-scrub-mnt-homelab.service
              touch "$out"
            '';
      };
    };
}
