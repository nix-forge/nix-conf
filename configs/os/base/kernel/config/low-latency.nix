{ lib, ... }:
let
  inherit (lib.kernel) yes unset freeform;
  inherit (lib.attrsets) mapAttrs;
  inherit (lib.modules) mkForce;
in
{
  boot.kernelPatches = [
    {
      name = "Lower latency";
      patch = null;
      extraStructuredConfig = mapAttrs (_: mkForce) {
        # Give the kernel a faster polling rate which is good on high end systems
        HZ = freeform "1000";
        HZ_1000 = yes;

        # Turn off other HZ options (250, 300, 500)
        HZ_250 = unset;
        HZ_300 = unset;
        HZ_500 = unset;
      };
    }
  ];
}
