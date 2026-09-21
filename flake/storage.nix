{ inputs, myLib, ... }: {
  # The disk installation VM is an explicit workstation target. Packages are
  # outside `nix flake check`, which keeps the heavy test optional locally.
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      packages = lib.optionalAttrs (system == "x86_64-linux") {
        desktop-storage-install = import ../tests/storage/install.nix {
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
