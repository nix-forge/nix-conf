{ pkgs, desktopConfig }:
let
  policy = desktopConfig.system.build.desktopMemoryPolicy;
  fixtures = pkgs.lib.fileset.toSource {
    root = ../systemd;
    fileset = pkgs.lib.fileset.unions [
      ../systemd/check-workstation-task.sh
      ../systemd/workstation_runner_fixture.py
      ../systemd/check-workstation-feedback.sh
      ../systemd/check_workstation_feedback.py
      ../systemd/check_workstation_lanes.py
      ../systemd/check_workstation_processes.py
      ../systemd/check_workstation_oom.py
      ../systemd/test_workstation_bounded.py
      ../systemd/workstation-task-child.sh
      ../systemd/workstation_task_child.py
    ];
  };
  python = pkgs.python3.withPackages (ps: [ ps.dbus-next ]);
  probe = pkgs.writeShellApplication {
    name = "workstation-native-check";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.strace
      pkgs.systemd
      pkgs.util-linux
      python
    ];
    text = (import ../../lib/templates/text.nix) ./scripts/desktop-workload-probe.sh {
      inherit fixtures policy;
      diskAdmissionCommand = pkgs.lib.escapeShellArg (
        pkgs.lib.escapeShellArg (pkgs.lib.getExe desktopConfig.system.build.desktopStorageCapacity)
      );
    };
  };
in
pkgs.testers.nixosTest {
  name = "desktop-workload-lifecycle";
  nodes.machine = {
    # The test intentionally exhausts a confined workload. Test instrumentation
    # otherwise panics the guest even for a cgroup-local OOM.
    boot.kernel.sysctl."vm.panic_on_oom" = 0;
    environment.systemPackages = [ probe ];
    services.dbus.enable = true;
    # The native isolation probes exercise the same CLI feature used by hosts.
    nix.settings.experimental-features = [ "nix-command" ];
    users.users.fixture = {
      isNormalUser = true;
      uid = 1000;
      linger = true;
    };
    systemd.user.slices.background-workload = {
      inherit (desktopConfig.systemd.user.slices.background-workload) description sliceConfig;
    };
    systemd.tmpfiles.rules = pkgs.lib.filter (
      rule: pkgs.lib.hasInfix "/run/workstation-workloads" rule
    ) desktopConfig.systemd.tmpfiles.rules;
    systemd.oomd.enable = true;
    # Feedback admission requires 3 GiB available, beyond the guest's own usage.
    virtualisation.memorySize = 4096;
    system.stateVersion = "26.05";
  };
  testScript = builtins.readFile ./scripts/desktop_workload_test.py;
}
