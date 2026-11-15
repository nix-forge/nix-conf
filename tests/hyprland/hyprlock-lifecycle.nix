{
  pkgs,
  hyprland,
  hyprlock,
}:
let
  inherit (pkgs) lib;
  # Public credentials belong only to this disposable authentication guest.
  password = "disposable-fixture-password";
  python = pkgs.python3.withPackages (ps: [
    ps.watchdog
    (import ../../lib/python/notification-process/package.nix { inherit pkgs; })
  ]);
  witness = pkgs.runCommandCC "hyprlock-egl-lifetime-witness" {
    buildInputs = [ pkgs.libglvnd ];
    witnessSource = ./fixtures/egl-lifetime-witness.c;
  } (builtins.readFile ./fixtures/build-egl-lifetime-witness.sh);
  command = lib.escapeShellArgs [
    (lib.getExe' pkgs.coreutils "env")
    "PYTHONPATH=/etc/locker-test"
    (lib.getExe python)
    "/etc/locker-test/hyprlock_lifecycle.py"
    "--cage"
    (lib.getExe pkgs.cage)
    "--sleep"
    (lib.getExe' pkgs.coreutils "sleep")
    "--hyprland"
    (lib.getExe hyprland)
    "--locker"
    (lib.getExe hyprlock)
    "--wtype"
    (lib.getExe pkgs.wtype)
    "--witness"
    witness
    "--config"
    "/etc/locker-test/hyprlock.conf"
    "--compositor-config"
    "/etc/locker-test/hyprland.lua"
    "--password"
    password
  ];
in
pkgs.testers.runNixOSTest {
  name = "hyprlock-session-lifecycle";
  nodes.machine = {
    system.stateVersion = "26.05";
    virtualisation = {
      memorySize = 3072;
      cores = 2;
      qemu.options = [
        "-vga none"
        "-device virtio-gpu-pci"
      ];
    };
    hardware.graphics.enable = true;
    fonts = {
      fontconfig.enable = true;
      packages = [ pkgs.dejavu_fonts ];
    };
    users.users.root = {
      # The test driver supplies an empty hashed-password file by default.
      hashedPasswordFile = lib.mkForce null;
      inherit password;
    };
    security.pam.services.hyprlock-fixture = { };
    environment.etc = {
      "locker-test/hyprlock_lifecycle.py".source = ./scripts/hyprlock_lifecycle.py;
      "locker-test/waits.py".source = ../waits.py;
      "locker-test/hyprland.lua".source = ./scripts/hypr-repro.lua;
      "locker-test/hyprlock.conf".source = ./fixtures/hyprlock-lifecycle.conf;
    };
  };
  testScript = (import ../../lib/templates/text.nix) ./scripts/hyprlock_lifecycle_vm_test.py {
    inherit command;
  };
}
