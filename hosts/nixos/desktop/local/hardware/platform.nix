{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "ahci"
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  # Keep this host's kernel command line narrowly tailored to its Zen 4
  # platform.  In particular, do not globally disable USB autosuspend or run
  # zswap on top of the configured zram swap device.
  boot.kernelParams = lib.mkForce [
    "amd_pstate=active"
    "root=fstab"
    "loglevel=3"
    "lsm=landlock,yama,bpf"
  ];
  boot.kernelModules = [
    "kvm-amd"
    "k10temp"
    "nct6683"
  ];
  boot.blacklistedKernelModules = [ "zenpower" ];
  boot.extraModprobeConfig = ''
    options kvm_amd nested=1
    # The board uses a Nuvoton NCT6687D-R.  The upstream nct6683 driver
    # supports it, but requires force=1 on non-Intel boards.
    options nct6683 force=1
    options cfg80211 ieee80211_regdom=US
  '';

  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.wirelessRegulatoryDatabase = true;

  services = {
    irqbalance.enable = true;
    smartd = {
      enable = true;
      autodetect = true;
      notifications.x11.enable = false;
    };
  };

  environment.systemPackages = with pkgs; [
    alsa-utils
    dmidecode
    efibootmgr
    ethtool
    iw
    lm_sensors
    nvme-cli
    pciutils
    smartmontools
    tpm2-tools
    usbutils
  ];
}
