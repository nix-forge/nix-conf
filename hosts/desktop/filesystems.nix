{ config, ... }:
{
  fileSystems =
    let
      mkFS = label: fsType: { inherit label fsType; };
      mkBTRFS =
        label:
        (mkFS label "btrfs")
        // {
          options = [
            "noatime"
            "compress-force=ztsd:1"
          ];
        };
      mkBoot = label: mkFS label "vfat";
      bootMP = config.boot.loader.efi.efiSysMountPoint;
    in
    {
      "/" = mkBTRFS "nixos";
      ${bootMP} = mkBoot "boot";
    };

  swapDevices = [ { label = "swap"; } ];

  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [ "/" ];
    interval = "monthly";
  };
}
