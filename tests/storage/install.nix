{ pkgs, diskoLib }:
let
  inherit (pkgs) lib;
  layout = import ../../hosts/nixos/desktop/disko.nix { inherit lib; };
  fixture = lib.recursiveUpdate layout {
    disko.devices.disk = {
      system.content.partitions = {
        ESP.size = "256M";
        swap.size = "256M";
        cryptroot.content = {
          passwordFile = "/tmp/secret.key";
          settings.keyFile = "/tmp/secret.key";
          extraFormatArgs = [
            "--type"
            "luks2"
            "--pbkdf"
            "argon2id"
            "--pbkdf-memory"
            "32768"
            "--pbkdf-force-iterations"
            "4"
          ];
        };
      };
      data.content.partitions.cryptdata.content = {
        passwordFile = "/tmp/secret.key";
        extraFormatArgs = [
          "--type"
          "luks2"
          "--pbkdf"
          "argon2id"
          "--pbkdf-memory"
          "32768"
          "--pbkdf-force-iterations"
          "4"
        ];
      };
    };
  };
in
diskoLib.testLib.makeDiskoTest {
  inherit pkgs;
  name = "desktop-encrypted-storage";
  disko-config = fixture;
  extraInstallerConfig.virtualisation.memorySize = 2048;
  extraSystemConfig = {
    imports = [ ../../hosts/nixos/desktop/local/storage/default.nix ];
    hardware.storage.encryptedRoot.enable = true;
    hardware.storage.encryptedRoot.backup = {
      paths = [ "/var/lib/desktop-storage" ];
      destinations.fixture = {
        repositoryFile = "/var/lib/desktop-backup-fixture/repository";
        passwordFile = "/var/lib/desktop-backup-fixture/password";
        requiredMounts = [ "/mnt/backup-fixture" ];
      };
    };
    # Exercise jobs explicitly; an elapsed timer must not race repository setup.
    systemd.timers.restic-backups-desktop-fixture.enable = false;
    systemd.timers.desktop-backup-verify-fixture.enable = false;
    boot.initrd.systemd.enable = true;
    users.users.ianmh = {
      isNormalUser = true;
      uid = 1000;
      group = "users";
    };
    virtualisation.libvirtd.enable = false;
  };
  postDisko = ''
    machine.succeed("install -d -m 700 /mnt/var/lib/desktop-storage/keys")
    machine.succeed("install -m 600 /tmp/secret.key /mnt/var/lib/desktop-storage/keys/data.key")
  '';
  extraTestScript = ''
    machine.wait_for_unit("desktop-data-ready.service")
    machine.succeed("cryptsetup isLuks --type luks2 /dev/disk/by-partlabel/NIXOS-CRYPTROOT")
    machine.succeed("cryptsetup isLuks --type luks2 /dev/disk/by-partlabel/NIXOS-CRYPTDATA")
    machine.succeed("mountpoint /srv/data/work; mountpoint /mnt/games; mountpoint /var/lib/libvirt/images")
    machine.succeed("btrfs filesystem usage / | grep 'Metadata,DUP'")
    swap = machine.succeed("awk 'NR == 2 {print $1}' /proc/swaps").strip()
    assert machine.succeed("lsblk -ndo TYPE " + swap).strip() == "crypt"
    machine.succeed("cryptsetup status " + swap)
    swap_uuid = machine.succeed("blkid -s UUID -o value " + swap).strip()
    machine.succeed("echo before > /home/history-test")
    machine.succeed("echo excluded > /home/ianmh/.local/share/docker/layer")
    snapshot = machine.succeed("snapper --no-dbus -c home create --read-only --print-number").strip()
    machine.succeed("echo after > /home/history-test")
    machine.succeed("grep before /home/.snapshots/" + snapshot + "/snapshot/history-test")
    machine.fail("test -e /home/.snapshots/" + snapshot + "/snapshot/ianmh/.local/share/docker/layer")
    machine.succeed("echo durable > /srv/data/work/reboot-test")
    # Disko starts QEMU without allow_reboot. A shutdown/start also exercises
    # genuine cold-boot key loading instead of retaining the running mapping.
    machine.shutdown()
    machine.start()
    machine.wait_for_unit("desktop-data-ready.service")
    machine.succeed("grep durable /srv/data/work/reboot-test")
    swap = machine.succeed("awk 'NR == 2 {print $1}' /proc/swaps").strip()
    assert machine.succeed("blkid -s UUID -o value " + swap).strip() != swap_uuid
    machine.succeed("install -d -m 700 /var/lib/desktop-backup-fixture /mnt/backup-fixture")
    machine.succeed("mount -t tmpfs -o size=128M tmpfs /mnt/backup-fixture")
    machine.succeed("umask 077; printf '%s\\n' /mnt/backup-fixture/repository > /var/lib/desktop-backup-fixture/repository; printf '%s\\n' public-disposable-test-password > /var/lib/desktop-backup-fixture/password")
    machine.succeed("RESTIC_REPOSITORY_FILE=/var/lib/desktop-backup-fixture/repository RESTIC_PASSWORD_FILE=/var/lib/desktop-backup-fixture/password restic init")
    machine.succeed("systemctl start restic-backups-desktop-fixture.service")
    machine.succeed("test -s /var/lib/desktop-storage/checks/fixture-backup.json")
    machine.succeed("systemctl start desktop-backup-verify-fixture.service")
    machine.succeed("test -s /var/lib/desktop-storage/checks/fixture-integrity.json; test -s /var/lib/desktop-storage/checks/fixture-restore.json")
    machine.fail("systemctl start desktop-backup-cold-fixture.service")
    backup_receipt = machine.succeed("cat /var/lib/desktop-storage/checks/fixture-backup.json")
    restore_receipt = machine.succeed("cat /var/lib/desktop-storage/checks/fixture-restore.json")
    machine.succeed("umount /mnt/backup-fixture")
    machine.fail("systemctl start restic-backups-desktop-fixture.service")
    machine.fail("systemctl start desktop-backup-verify-fixture.service")
    assert machine.succeed("cat /var/lib/desktop-storage/checks/fixture-backup.json") == backup_receipt
    assert machine.succeed("cat /var/lib/desktop-storage/checks/fixture-restore.json") == restore_receipt
    machine.fail("test -e /mnt/backup-fixture/repository")
    machine.fail("desktop-backup-check status")
    # Remove only the fixture's runtime data key. On the next cold boot,
    # headless crypttab cannot create cryptdata and must not delay root login.
    machine.succeed("mv /var/lib/desktop-storage/keys/data.key /var/lib/desktop-storage/keys/data.unavailable")
    machine.shutdown()
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mountpoint /home")
    machine.fail("mountpoint /srv/data")
    machine.fail("test -e /dev/mapper/cryptdata")
    machine.fail("systemctl start desktop-data-ready.service")
    machine.fail("test -e /mnt/games/steamapps")
    machine.succeed("systemctl start desktop-snapshot-home-timeline.service")
    machine.succeed("systemctl start desktop-snapshot-home-cleanup.service")
    # An unavailable data mount may fail its dependency or skip the mount
    # condition. Either outcome must leave the underlying root directory alone.
    machine.execute("systemctl start desktop-snapshot-data-timeline.service")
    machine.fail("test -d /srv/data/.snapshots")
  '';
}
