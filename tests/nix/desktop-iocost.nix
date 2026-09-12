{ pkgs }:
let
  disk = pkgs.runCommand "iocost-test-disk" { } ''
    truncate -s 128M "$out"
  '';
in
pkgs.testers.nixosTest {
  name = "desktop-iocost";
  nodes.machine = {
    imports = [ ../../hosts/nixos/desktop/local/iocost.nix ];
    virtualisation.qemu.options = [
      "-drive file=${disk},format=raw,if=none,id=iocost-test,snapshot=on"
      "-device nvme,drive=iocost-test,serial=iocost-test"
    ];
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("desktop-iocost.service")
    device = machine.succeed("cat /sys/block/nvme0n1/dev").strip()
    # The guest's kernel may default to mq-deadline. Reproduce the desktop's
    # none scheduler explicitly before checking controller independence.
    machine.succeed("echo none > /sys/block/nvme0n1/queue/scheduler")

    def assert_enabled():
        lines = machine.succeed("cat /sys/fs/cgroup/io.cost.qos").splitlines()
        settings = next(line.split()[1:] for line in lines if line.split()[0] == device)
        assert "enable=1" in settings, settings
        assert "ctrl=auto" in settings, settings
        model = machine.succeed("cat /sys/fs/cgroup/io.cost.model")
        assert any(line.startswith(device + " ") and "ctrl=auto" in line for line in model.splitlines()), model

    assert_enabled()
    # This controller works with the ordinary NVMe scheduler; it does not
    # require replacing the scheduler with BFQ.
    assert "[none]" in machine.succeed("cat /sys/block/nvme0n1/queue/scheduler")
    machine.succeed(f"echo '{device} enable=0' > /sys/fs/cgroup/io.cost.qos")
    machine.succeed("udevadm trigger --action=change /sys/block/nvme0n1 && udevadm settle")
    assert_enabled()
    # Reapplying the service also handles already enumerated drives.
    machine.succeed(f"echo '{device} enable=0' > /sys/fs/cgroup/io.cost.qos")
    machine.succeed("systemctl restart desktop-iocost.service")
    assert_enabled()
    machine.succeed("systemd-run --unit=iocost-user-check --slice=user.slice sleep 10")
    assert "default 200" in machine.succeed("cat /sys/fs/cgroup/user.slice/io.weight")
  '';
}
