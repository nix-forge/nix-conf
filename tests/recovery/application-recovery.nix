{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "application-recovery-lifecycle";
  nodes.machine = { pkgs, ... }: {
    imports = [ ../../modules/nixos/services/application-recovery ];
    systemd.tmpfiles.rules = [ "d /var/lib/recovery-fixture 0700 root root - -" ];
    systemd.services.fixture-writer = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
    };
    services.applicationRecovery.applications = {
      fixture = {
        units = [ "fixture-writer.service" ];
        packages = [
          pkgs.coreutils
          pkgs.gnugrep
        ];
        export = ''
          test "$(systemctl is-active fixture-writer.service)" = inactive
          cp /var/lib/recovery-fixture/live "$RECOVERY_EXPORT/record"
        '';
        backup = ''cp "$RECOVERY_EXPORT/record" /var/lib/recovery-fixture/archive'';
        recover = ''cp /var/lib/recovery-fixture/archive "$RECOVERY_EXPORT/record"'';
        restore = ''cp "$RECOVERY_EXPORT/record" "$RECOVERY_TARGET/restored"'';
        check = ''
          grep -Fx persisted-generation-2 "$RECOVERY_TARGET/restored"
          # The drill's systemd namespace must reject live-state writes.
          if touch /var/lib/recovery-fixture/forbidden; then exit 1; fi
        '';
      };
      failing = {
        units = [ "fixture-writer.service" ];
        export = "exit 23";
        backup = "exit 99";
        recover = "exit 99";
        restore = "exit 99";
        check = "exit 99";
      };
    };
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("fixture-writer.service")
    machine.succeed("echo persisted-generation-2 > /var/lib/recovery-fixture/live")
    machine.succeed("systemctl start application-recovery-fixture-backup.service")
    machine.wait_for_unit("fixture-writer.service")
    machine.succeed("rm /var/lib/recovery-fixture/live")
    machine.succeed("systemctl start application-recovery-fixture-drill.service")
    machine.succeed("test -f /var/lib/application-recovery/fixture/drill-success.json")
    machine.fail("test -e /var/lib/recovery-fixture/forbidden")
    machine.fail("systemctl start application-recovery-failing-backup.service")
    machine.wait_for_unit("fixture-writer.service")
    machine.fail("test -e /var/lib/application-recovery/failing/backup-success.json")
    machine.succeed("test -f /var/lib/application-recovery/failing/backup-attempt.json")
  '';
}
