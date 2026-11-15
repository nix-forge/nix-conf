{
  pkgs,
  hyprland,
  expectFailure ? false,
}:
let
  guestPython = import ./guest-python.nix { inherit pkgs; };
  client = import ./subsurface-rounding-client.nix { inherit pkgs; };
  python = pkgs.python3.withPackages (p: [
    p.pillow
    p.watchdog
    (import ../../lib/python/notification-process/package.nix { inherit pkgs; })
  ]);
in
pkgs.testers.runNixOSTest {
  name = "hyprland-subsurface-rounding${pkgs.lib.optionalString expectFailure "-baseline"}";
  nodes.machine = {
    system.stateVersion = "26.05";
    virtualisation = {
      memorySize = 2048;
      cores = 2;
      qemu.options = [
        "-vga none"
        "-device virtio-gpu-pci"
      ];
    };
    hardware.graphics.enable = true;
    services.seatd.enable = true;
    services.dbus.enable = true;
    services.journald.settings.Journal = {
      ForwardToConsole = pkgs.lib.mkForce false;
      RuntimeMaxUse = "16M";
      MaxLevelStore = "info";
    };
    environment = {
      systemPackages = [
        hyprland
        client
        python
        pkgs.wayland-utils
        pkgs.grim
        pkgs.mesa
      ];
      etc."rounding-observer".source = guestPython;
      etc."compositor_events.py".source = "${guestPython}/compositor_events.py";
      etc."verify-rounding.py".source = "${guestPython}/verify-rounding.py";
      etc."hypr-repro.lua".source = ./scripts/hypr-repro.lua;
    };
  };
  testScript = (import ../../lib/templates/text.nix) ./scripts/subsurface_rounding_vm_test.py {
    expectFailure = if expectFailure then "True" else "False";
  };
}
