{ pkgs, myLib }:
pkgs.testers.runNixOSTest {
  name = "application-recovery-lifecycle";
  node.specialArgs = { inherit myLib; };
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
        export = builtins.readFile ./scripts/application-recovery-lifecycle.sh;
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
  testScript = builtins.readFile ./scripts/application_recovery_test.py;
}
