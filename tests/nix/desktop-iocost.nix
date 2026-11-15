{ pkgs }:
let
  disk = pkgs.runCommand "iocost-test-disk" { } ''
    truncate -s 128M "$out"
  '';
in
pkgs.testers.nixosTest {
  name = "desktop-iocost";
  nodes.machine = {
    imports = [
      ../../modules/nixos/hardware/iocost.nix
      ../../hosts/nixos/desktop/local/iocost.nix
    ];
    virtualisation.qemu.options = [
      "-drive file=${disk},format=raw,if=none,id=iocost-test,snapshot=on"
      "-device nvme,drive=iocost-test,serial=iocost-test"
    ];
  };
  testScript = builtins.readFile ./scripts/desktop_iocost_test.py;
}
