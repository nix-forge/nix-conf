"""Exercise the installed encrypted-storage policy with the NixOS VM driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    machine: QemuMachine = cast("QemuMachine", None)

machine.succeed("test -d /sys/firmware/efi && mountpoint -q /boot")
machine.fail("su -s /bin/sh ianmh -c 'ls /boot'")
machine.wait_for_unit("desktop-data-ready.service")
machine.succeed("systemctl start desktop-home-subvolumes.service")
machine.succeed(
    "systemctl show systemd-user-sessions.service -p Requires --value | grep -F desktop-home-subvolumes.service"
)
machine.succeed("cryptsetup isLuks --type luks2 /dev/disk/by-partlabel/NIXOS-CRYPTROOT")
machine.succeed("cryptsetup isLuks --type luks2 /dev/disk/by-partlabel/NIXOS-CRYPTDATA")
machine.succeed("cryptsetup isLuks --type luks2 /dev/disk/by-partlabel/HOMELAB-CRYPT")
machine.succeed("test -d /mnt/homelab/media && test -d /mnt/homelab/backups")
machine.succeed("findmnt -rn -t btrfs --mountpoint /mnt/homelab")
machine.succeed(
    "btrfs subvolume show /mnt/homelab/media; btrfs subvolume show /mnt/homelab/backups"
)
assert machine.succeed("stat -c '%u:%g:%a' /mnt/homelab/backups").strip() == "0:0:700"
machine.succeed("btrfs filesystem usage /mnt/homelab | grep 'Metadata,DUP'")
machine.succeed("echo durable > /mnt/homelab/media/reboot-test")
options = (
    machine
    .succeed("findmnt -rn -t btrfs -o VFS-OPTIONS --mountpoint /mnt/homelab")
    .strip()
    .split(",")
)
assert all(option in options for option in ["nodev", "nosuid", "noexec"]), options
machine.succeed(
    "mountpoint /srv/data/work; mountpoint /mnt/games; mountpoint /var/lib/libvirt/images"
)
# Steam tests write and execute access at the library root before it offers
# the separate games filesystem in its storage picker.
machine.succeed(
    "su -s /bin/sh ianmh -c 'touch /mnt/games/.steam_exec_test.sh && rm /mnt/games/.steam_exec_test.sh'"
)
for path in ["/srv/data", "/srv/data/work", "/mnt/games", "/var/lib/libvirt/images"]:
    options = (
        machine
        .succeed("findmnt -n -o VFS-OPTIONS --mountpoint " + path)
        .strip()
        .split(",")
    )
    assert "nodev" in options, (path, options)
    assert "nosuid" in options, (path, options)
machine.succeed("btrfs filesystem usage / | grep 'Metadata,DUP'")
for path in ["/home/.snapshots", "/srv/data/.snapshots", "/srv/data/work/.snapshots"]:
    assert machine.succeed("stat -c '%u:%g:%a' " + path).strip() == "0:0:700"
swap = machine.succeed("awk 'NR == 2 {print $1}' /proc/swaps").strip()
assert machine.succeed("lsblk -ndo TYPE " + swap).strip() == "crypt"
machine.succeed("cryptsetup status " + swap)
swap_uuid = machine.succeed("blkid -s UUID -o value " + swap).strip()
machine.succeed("echo before > /home/history-test")
for user in ["ianmh", "alex"]:
    machine.succeed(
        "grep -Fq '/home/"
        + user
        + "/.local/share/docker' /nix/store/*-desktop-backup-policy.json"
    )
    group = "users" if user == "ianmh" else "alex"
    for path in [".cache", ".local/share/docker"]:
        full_path = "/home/" + user + "/" + path
        machine.succeed("btrfs subvolume show " + full_path)
        assert (
            machine.succeed("stat -c '%U:%G:%a' " + full_path).strip()
            == user + ":" + group + ":700"
        )
    machine.succeed(
        "su -s /bin/sh "
        + user
        + " -c 'echo excluded > /home/"
        + user
        + "/.local/share/docker/layer'"
    )
    machine.succeed(
        "su -s /bin/sh "
        + user
        + " -c 'echo cache > /home/"
        + user
        + "/.cache/disposable'"
    )
machine.fail("su -s /bin/sh ianmh -c 'ls /home/.snapshots'")
machine.fail("su -s /bin/sh alex -c 'ls /home/ianmh/.cache'")
snapshot = machine.succeed(
    "snapper --no-dbus -c home create --read-only --print-number"
).strip()
machine.succeed("echo after > /home/history-test")
machine.succeed("grep before /home/.snapshots/" + snapshot + "/snapshot/history-test")
for user in ["ianmh", "alex"]:
    machine.fail(
        "test -e /home/.snapshots/"
        + snapshot
        + "/snapshot/"
        + user
        + "/.local/share/docker/layer"
    )
    machine.fail(
        "test -e /home/.snapshots/"
        + snapshot
        + "/snapshot/"
        + user
        + "/.cache/disposable"
    )
# Restoring a directory can restore NOCOW too. Preparation must clear it
# before new images are created, without rewriting existing image files.
machine.succeed(
    "chattr +C /var/lib/libvirt/images; systemctl restart desktop-data-ready.service"
)
machine.succeed("touch /var/lib/libvirt/images/checksummed-image")
assert (
    "C"
    not in machine.succeed("lsattr /var/lib/libvirt/images/checksummed-image").split()[
        0
    ]
)
machine.succeed("echo durable > /srv/data/work/reboot-test")
# Disko starts QEMU without allow_reboot. A shutdown/start also exercises
# genuine cold-boot key loading instead of retaining the running mapping.
machine.shutdown()
machine.start()
machine.wait_for_unit("desktop-data-ready.service")
machine.succeed("grep durable /srv/data/work/reboot-test")
machine.succeed("grep durable /mnt/homelab/media/reboot-test")
swap = machine.succeed("awk 'NR == 2 {print $1}' /proc/swaps").strip()
assert machine.succeed("blkid -s UUID -o value " + swap).strip() != swap_uuid
machine.succeed("install -d -m 700 /var/lib/desktop-backup-fixture /mnt/backup-fixture")
machine.succeed("mount -t tmpfs -o size=128M tmpfs /mnt/backup-fixture")
machine.succeed(
    "umask 077; printf '%s\\n' /mnt/backup-fixture/repository > /var/lib/desktop-backup-fixture/repository; printf '%s\\n' public-disposable-test-password > /var/lib/desktop-backup-fixture/password"
)
machine.succeed(
    "RESTIC_REPOSITORY_FILE=/var/lib/desktop-backup-fixture/repository RESTIC_PASSWORD_FILE=/var/lib/desktop-backup-fixture/password restic init"
)
machine.succeed("systemctl start restic-backups-desktop-fixture.service")
machine.succeed("test -s /var/lib/desktop-storage/checks/fixture-backup.json")
machine.succeed("systemctl start desktop-backup-verify-fixture.service")
machine.succeed(
    "test -s /var/lib/desktop-storage/checks/fixture-integrity.json; test -s /var/lib/desktop-storage/checks/fixture-restore.json"
)
machine.fail("systemctl start desktop-backup-cold-fixture.service")
backup_receipt = machine.succeed(
    "cat /var/lib/desktop-storage/checks/fixture-backup.json"
)
restore_receipt = machine.succeed(
    "cat /var/lib/desktop-storage/checks/fixture-restore.json"
)
machine.succeed("umount /mnt/backup-fixture")
machine.fail("systemctl start restic-backups-desktop-fixture.service")
machine.fail("systemctl start desktop-backup-verify-fixture.service")
assert (
    machine.succeed("cat /var/lib/desktop-storage/checks/fixture-backup.json")
    == backup_receipt
)
assert (
    machine.succeed("cat /var/lib/desktop-storage/checks/fixture-restore.json")
    == restore_receipt
)
machine.fail("test -e /mnt/backup-fixture/repository")
machine.fail("desktop-backup-check status")
# Remove only the fixture's runtime data key. On the next cold boot,
# headless crypttab cannot create cryptdata and must not delay root login.
machine.succeed(
    "mv /var/lib/desktop-storage/keys/data.key /var/lib/desktop-storage/keys/data.unavailable"
)
machine.succeed(
    "mv /var/lib/desktop-storage/keys/homelab.key /var/lib/desktop-storage/keys/homelab.unavailable"
)
machine.shutdown()
machine.start()
machine.wait_for_unit("multi-user.target")
machine.succeed(
    "systemd-analyze verify --man=no /etc/systemd/system/btrfs-scrub*.timer"
)
machine.succeed("mountpoint /home")
machine.fail("mountpoint /srv/data")
machine.fail("findmnt -rnC -t btrfs --mountpoint /mnt/homelab")
machine.succeed("systemctl start btrfs-scrub-mnt-homelab.service")
machine.fail("findmnt -rnC -t btrfs --mountpoint /mnt/homelab")
machine.fail("test -e /dev/mapper/cryptdata")
machine.fail("systemctl start desktop-data-ready.service")
machine.fail("test -e /mnt/games/steamapps")
machine.succeed("systemctl start desktop-snapshot-home-timeline.service")
machine.succeed("systemctl start desktop-snapshot-home-cleanup.service")
# An unavailable data mount may fail its dependency or skip the mount
# condition. Either outcome must leave the underlying root directory alone.
machine.execute("systemctl start desktop-snapshot-data-timeline.service")
machine.fail("test -d /srv/data/.snapshots")
machine.execute("systemctl start btrfs-scrub@srv-data.service")
# The service must neither start a root scrub nor write data-drive status.
assert (
    machine.succeed(
        "systemctl show btrfs-scrub@srv-data.service -p ExecMainStartTimestampMonotonic --value"
    ).strip()
    == "0"
)
machine.succeed("btrfs scrub status / | grep 'no stats available'")
# A restored plain directory must not silently enter home snapshots.
machine.succeed(
    "mv /home/alex/.cache /home/alex/cache-subvolume-old; mkdir -m 700 /home/alex/.cache"
)
machine.fail("systemctl restart desktop-home-subvolumes.service")
machine.fail("systemctl start desktop-snapshot-home-timeline.service")
machine.succeed(
    "rmdir /home/alex/.cache; mv /home/alex/cache-subvolume-old /home/alex/.cache"
)
# The deliberate failed attempts can exhaust systemd's start rate limit.
# Recovery clears the failed state only after restoring the subvolume.
machine.succeed("systemctl reset-failed desktop-home-subvolumes.service")
machine.succeed("systemctl start desktop-home-subvolumes.service")
