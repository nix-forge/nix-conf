{ pkgs, desktopConfig }:
let
  initialization = desktopConfig.systemd.services.mkswap-swap-workstation;
in
pkgs.testers.nixosTest {
  name = "desktop-swap-boot";
  nodes.machine = {
    # Exercise the production ordering and directory preparation on a fresh
    # filesystem. Only the allocation size differs from the workstation.
    # qemu-vm disables swap at priority 10, stronger than ordinary mkForce.
    swapDevices = pkgs.lib.mkOverride 0 (
      map (swap: {
        inherit (swap) device priority;
        size = 16;
      }) (pkgs.lib.filter (swap: swap.device == "/swap/workstation") desktopConfig.swapDevices)
    );
    systemd.services.mkswap-swap-workstation = { inherit (initialization) after requires preStart; };
    systemd.tmpfiles.rules = pkgs.lib.filter (
      rule: pkgs.lib.hasInfix "/swap " rule
    ) desktopConfig.systemd.tmpfiles.rules;
    users.users.fixture = {
      isNormalUser = true;
      uid = 1000;
      linger = true;
    };
    virtualisation.memorySize = 1024;
    system.stateVersion = "26.05";
  };
  testScript = builtins.readFile ./scripts/desktop_swap_boot_test.py;
}
