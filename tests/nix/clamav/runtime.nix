{ pkgs }:
let
  # Exercise the real daemon, fd-passing protocol, units and namespaces with
  # a local signature. Only the network-blocked updater is a fixture.
  fixtureDatabase = ./fixtures/local.ndb;
  readyProbe = pkgs.writers.writePython3Bin "clamav-fixture-ready" {
    flakeIgnore = [ "E501" ];
  } ./scripts/check_daemon_ready.py;
  updater = pkgs.writeShellScriptBin "freshclam" (
    (import ../../../lib/templates/text.nix) ./scripts/freshclam.sh {
      pkgs_coreutils = pkgs.coreutils;
      inherit fixtureDatabase;
    }
  );
  fixture = pkgs.symlinkJoin {
    name = "clamav-lifecycle-fixture";
    paths = [ pkgs.clamav ];
    postBuild = (import ../../../lib/templates/text.nix) ./scripts/install-updater.sh {
      freshclam = pkgs.lib.escapeShellArg (pkgs.lib.getExe updater);
    };
  };
in
pkgs.testers.nixosTest {
  name = "clamav-offline-boot-and-scan-visibility";
  nodes.machine = { config, lib, ... }: {
    imports = [
      ../../../modules/nixos/security/clamav.nix
      ../../../hosts/nixos/desktop/local/security/clamav.nix
    ];
    services.clamav = {
      package = fixture;
      clamonacc.enable = lib.mkForce false;
      # Exercise a valid smaller capacity than the desktop's four-thread policy.
      daemon.settings = {
        MaxThreads = lib.mkForce 1;
        MaxQueue = lib.mkForce 2;
      };
    };
    environment.systemPackages = [ readyProbe ];
    environment.etc."clamav/fixture-socket".text = config.services.clamav.daemon.settings.LocalSocket;
    # Accelerate recovery in the guest. Production uses a 30-second retry.
    systemd.services.clamav-daemon = {
      serviceConfig.RestartSec = lib.mkForce "1s";
      unitConfig.StartLimitIntervalSec = 0;
    };
    systemd.tmpfiles.rules = [
      "p /run/fixture-network-online 0600 clamav clamav -"
      "d /var/lib/clamav 0755 clamav clamav -"
      "C /var/lib/clamav/fixture.ndb - - - - ${fixtureDatabase}"
    ];
  };
  testScript = builtins.readFile ./scripts/runtime_test.py;
}
