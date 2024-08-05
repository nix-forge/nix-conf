{ lib, ... }:
let
  inherit (lib.kernel) yes no;
  inherit (lib.attrsets) mapAttrs;
  inherit (lib.modules) mkForce;
in
{
  boot.kernelPatches = [
    {
      name = "zstd-module-compression";
      patch = null;
      extraStructuredConfig = mapAttrs (_: mkForce) {
        KERNEL_ZSTD = yes;
        MODULE_COMPRESS_ZSTD = yes;
        MODULE_COMPRESS_XZ = no;
      };
    }
  ];
}
