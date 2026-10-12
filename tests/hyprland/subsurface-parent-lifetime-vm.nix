{
  pkgs,
  unpatched,
  patched,
}:
let
  fixture = pkgs.lib.fileset.toSource {
    root = ./.;
    fileset = pkgs.lib.fileset.unions [
      ./check-subsurface-teardown.sh
      ./subsurface-parent-teardown.c
    ];
  };
  node =
    compositor:
    let
      executable = pkgs.writeShellApplication {
        name = "hyprland-lifetime-under-test";
        text = ''
          exec ${pkgs.lib.getExe compositor} --i-am-really-stupid "$@"
        '';
      };
    in
    {
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
      boot.kernelModules = [ "virtio_gpu" ];
      environment = {
        systemPackages = [
          compositor
          executable
          pkgs.cage
          pkgs.jq
          pkgs.pkg-config
          pkgs.stdenv.cc
          pkgs.wayland
          (pkgs.lib.getBin pkgs.wayland-scanner)
        ];
        variables = {
          HYPRLAND_UNDER_TEST = pkgs.lib.getExe executable;
          PKG_CONFIG_PATH = "${pkgs.wayland.dev}/lib/pkgconfig:${pkgs.wayland-protocols}/share/pkgconfig";
        };
        etc = {
          "lifetime-probe/check-subsurface-teardown.sh".source = "${fixture}/check-subsurface-teardown.sh";
          "lifetime-probe/subsurface-parent-teardown.c".source = "${fixture}/subsurface-parent-teardown.c";
        };
      };
    };
in
pkgs.testers.runNixOSTest {
  name = "hyprland-subsurface-parent-lifetime";
  nodes = {
    baseline = node unpatched;
    repaired = node patched;
  };
  testScript = builtins.readFile ./subsurface_parent_lifetime_vm.py;
}
