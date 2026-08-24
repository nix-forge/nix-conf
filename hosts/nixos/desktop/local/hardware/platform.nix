{
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
  # The system volume is a Btrfs filesystem on this NVMe controller. Keep the
  # drivers needed before the real root mounts with this host rather than in a
  # shared boot profile.
  boot.initrd.kernelModules = [
    "nvme"
    "btrfs"
  ];
  # Capture reliability takes precedence over scheduler tuning: the prior
  # XanMod build reproduced an AMD-Vi/firewire_ohci DMA fault. Use the matching
  # upstream kernel as this host's ordinary kernel for a controlled comparison.
  # This is not a boot specialisation.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
  # Keep this host's kernel command line narrowly tailored to its Zen 4
  # platform. In particular, do not globally disable USB autosuspend or run
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

  # Zen 4 receives vendor microcode through the initrd before the kernel
  # starts normal userspace. Keep this explicit for this AMD physical host;
  # it must not depend on a shared firmware-policy default.
  hardware.cpu.amd.updateMicrocode = true;
  hardware.wirelessRegulatoryDatabase = true;

  # This mains-powered MediaTek controller advertises Fast Connectable support.
  # Favor faster reconnection of the desktop's established audio peripherals;
  # a modest resume delay also lets the shared Wi-Fi/BT radio settle first.
  hardware.bluetooth.settings = {
    General.FastConnectable = true;
    Policy.ResumeDelay = 3;
  };

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
