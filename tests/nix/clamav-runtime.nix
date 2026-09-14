{ pkgs }:
let
  # Exercise the real NixOS units and namespaces without downloading virus
  # databases or contacting a public mirror. The fixture models clamd's
  # requirement for an installed database and a network-blocked updater.
  fixture = pkgs.symlinkJoin {
    name = "clamav-lifecycle-fixture";
    paths = [
      (pkgs.writeShellScriptBin "clamd" ''
        set -eu
        test -f /var/lib/clamav/fixture-db
        touch /run/clamav/fixture-ready
        exec ${pkgs.coreutils}/bin/sleep infinity
      '')
      (pkgs.writeShellScriptBin "freshclam" ''
        set -eu
        until test -f /run/fixture-network-online; do
          ${pkgs.coreutils}/bin/sleep 1
        done
        touch /var/lib/clamav/fixture-db
      '')
      (pkgs.writeShellScriptBin "clamdscan" ''
        set -eu
        test -f /tmp/host-scan-canary
        test -f /var/tmp/host-scan-canary
      '')
    ];
  };
in
pkgs.testers.nixosTest {
  name = "clamav-offline-boot-and-scan-visibility";
  nodes.machine = { lib, ... }: {
    imports = [
      ../../modules/nixos/security/clamav.nix
      ../../hosts/nixos/desktop/local/security-clamav.nix
    ];
    services.clamav = {
      package = fixture;
      clamonacc.enable = lib.mkForce false;
    };
    # Accelerate recovery in the guest. Production uses a 30-second retry.
    systemd.services.clamav-daemon = {
      serviceConfig.RestartSec = lib.mkForce "1s";
      unitConfig.StartLimitIntervalSec = 0;
    };
    systemd.tmpfiles.rules = [
      "d /var/lib/clamav 0755 clamav clamav -"
      "f /var/lib/clamav/fixture-db 0644 clamav clamav - fixture"
    ];
  };
  testScript = ''
    machine.start()
    # With the old dependency, freshclam waits forever for this offline
    # machine and neither clamd nor multi-user.target completes startup.
    machine.wait_for_unit("multi-user.target", timeout=30)
    machine.wait_until_succeeds("test -f /run/clamav/fixture-ready", timeout=10)
    machine.succeed("systemctl start --no-block clamav-freshclam.service")
    machine.wait_until_succeeds(
        "test $(systemctl show -p ActiveState --value clamav-freshclam.service) = activating"
    )
    machine.succeed("systemctl is-active clamav-daemon.service")

    # A missing database must fail visibly and recover after a successful
    # update without an operator restarting the daemon.
    machine.succeed("systemctl stop clamav-daemon.service")
    machine.fail("test -e /run/clamav/fixture-ready")
    machine.succeed("rm /var/lib/clamav/fixture-db")
    machine.succeed("systemctl start clamav-daemon.service")
    machine.wait_until_succeeds(
        "test $(systemctl show -p NRestarts --value clamav-daemon.service) -gt 0"
    )
    machine.succeed("touch /run/fixture-network-online")
    machine.wait_until_succeeds("test -f /run/clamav/fixture-ready", timeout=15)
    machine.succeed("systemctl is-active clamav-daemon.service")

    # These are host files. PrivateTmp=true makes the scheduled scan fail
    # because its namespace cannot see either marker.
    machine.succeed("touch /tmp/host-scan-canary /var/tmp/host-scan-canary")
    machine.succeed("systemctl start clamdscan.service")
    machine.succeed("test $(systemctl show -p Result --value clamdscan.service) = success")
  '';
}
