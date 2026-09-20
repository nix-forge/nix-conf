{
  inputs,
  myLib,
  ...
}:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        application-recovery = import ../../tests/recovery/application-recovery.nix { inherit pkgs; };
        desktop-storage-install = import ../../tests/storage/install.nix {
          inherit pkgs myLib;
          diskoLib = import "${inputs.disko}/lib" {
            inherit lib;
            makeTest = import "${inputs.nixpkgs}/nixos/tests/make-test-python.nix";
            eval-config = import "${inputs.nixpkgs}/nixos/lib/eval-config.nix";
            qemu-common = import "${inputs.nixpkgs}/nixos/lib/qemu-common.nix";
          };
        };
      };
    };
}
