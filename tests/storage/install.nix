{
  pkgs,
  diskoLib,
  myLib,
}:
let
  inherit (pkgs) lib;
  layout =
    lib.recursiveUpdate
      ((import ../../hosts/nixos/desktop/local/storage/disk-layout.nix { }).lib.desktopDiskLayout {
        inherit lib;
      })
      (
        (import ../../hosts/nixos/desktop/local/storage/homelab-disk-layout.nix { }).lib.homelabDiskLayout {
          inherit lib;
        }
      );
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
      homelab.content.partitions.crypt.content = {
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
  };
in
diskoLib.testLib.makeDiskoTest {
  inherit pkgs;
  name = "desktop-encrypted-storage";
  disko-config = fixture;
  efi = true;
  extraInstallerConfig.virtualisation.memorySize = 2048;
  extraSystemConfig = {
    _module.args = { inherit myLib; };
    imports = [
      ../../hosts/nixos/desktop/local/storage/default.nix
      ../../hosts/nixos/desktop/local/hardware/filesystems.nix
    ];
    hardware.storage.encryptedRoot.enable = true;
    hardware.storage.homelabHdd.enable = true;
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
    systemd.timers."btrfs-scrub@".timerConfig.Persistent = lib.mkForce false;
    users.users.ianmh = {
      isNormalUser = true;
      uid = 1000;
      group = "users";
    };
    users.users.alex = {
      isNormalUser = true;
      uid = 1001;
      group = "alex";
    };
    users.groups.alex = { };
    virtualisation.libvirtd.enable = false;
    environment.systemPackages = [ pkgs.e2fsprogs ];
  };
  postDisko = builtins.readFile ./scripts/desktop_encrypted_storage.py;
  extraTestScript = builtins.readFile ./scripts/desktop_storage_extra_test.py;
}
