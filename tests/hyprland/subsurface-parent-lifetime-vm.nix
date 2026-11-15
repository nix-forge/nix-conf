{
  pkgs,
  unpatched,
  patched,
  parentOnly ? false,
}:
let
  guestPython = import ./guest-python.nix { inherit pkgs; };
  probe =
    pkgs.runCommand "hyprland-parent-lifetime-client"
      {
        nativeBuildInputs = [
          pkgs.stdenv.cc
          pkgs.pkg-config
          pkgs.wayland-scanner
        ];
        buildInputs = [
          pkgs.wayland
          pkgs.wayland-protocols
        ];
      }
      ''
        protocols=$(pkg-config --variable=pkgdatadir wayland-protocols)
        wayland-scanner client-header "$protocols/stable/xdg-shell/xdg-shell.xml" xdg-shell-client-protocol.h
        wayland-scanner private-code "$protocols/stable/xdg-shell/xdg-shell.xml" xdg-shell-protocol.c
        wayland-scanner client-header "$protocols/staging/color-management/color-management-v1.xml" color-management-v1-client-protocol.h
        wayland-scanner private-code "$protocols/staging/color-management/color-management-v1.xml" color-management-v1-protocol.c
        $CC -std=c17 -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Werror \
          $(pkg-config --cflags wayland-client) -I. -c ${./subsurface-parent-teardown.c} -o client.o
        mkdir -p "$out/bin"
        $CC client.o xdg-shell-protocol.c color-management-v1-protocol.c \
          $(pkg-config --cflags --libs wayland-client) -o "$out/bin/lifetime-client"
      '';
  python = pkgs.python3.withPackages (ps: [
    ps.watchdog
    ps.dbus-next
    (import ../../lib/python/notification-process/package.nix { inherit pkgs; })
  ]);
  node = compositor: {
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
    environment.systemPackages = [
      compositor
      probe
      python
      pkgs.wayland-utils
    ];
    environment.etc."lifetime-observer".source = guestPython;
    environment.etc."lifetime-proof.lua".text = ''
      hl.config({ animations = { enabled = false }, misc = { disable_watchdog_warning = true }, debug = { disable_logs = false, enable_stdout_logs = true, colored_stdout_logs = false } })
      hl.monitor({ output = "", mode = "1280x720@60", position = "0x0", scale = 1 })
    '';
  };
in
pkgs.testers.runNixOSTest {
  name = if parentOnly then "hyprland-parent-display" else "hyprland-subsurface-parent-lifetime";
  nodes = {
    baseline = node unpatched;
  }
  // pkgs.lib.optionalAttrs (!parentOnly) { repaired = node patched; };
  testScript =
    pkgs.lib.replaceStrings
      [ "from hyprland.lifetime import lifetime_contract" "lifetime_contract." ]
      [ (builtins.readFile ./lifetime/lifetime_contract.py) "" ]
      (
        pkgs.lib.optionalString parentOnly "parent_only = True\n"
        + builtins.readFile ./subsurface_parent_lifetime_vm.py
      );
}
