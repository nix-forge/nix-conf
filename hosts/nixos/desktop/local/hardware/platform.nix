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
  # Keep this host's additions narrowly tailored to its Zen 4 platform. Do
  # not force-replace the whole command line: NixOS derives the LSM sequence
  # and AppArmor's activation parameter from enabled security modules. In
  # particular, do not globally disable USB autosuspend or run zswap on top
  # of the configured zram swap device.
  boot.kernelParams = [ "amd_pstate=active" ];
  # Use NixOS's console-level option rather than a duplicate kernel argument,
  # so both the early kernel command line and runtime printk setting agree.
  boot.consoleLogLevel = 3;
  boot.kernelModules = [
    "kvm-amd"
    "k10temp"
    "nct6683"
  ];
  boot.blacklistedKernelModules = [ "zenpower" ];
  boot.extraModprobeConfig = builtins.readFile ./platform-modprobe.conf;

  # Zen 4 receives vendor microcode through the initrd before the kernel
  # starts normal userspace. Keep this explicit for this AMD physical host;
  # it must not depend on a shared firmware-policy default.
  hardware.cpu.amd.updateMicrocode = true;
  hardware.wirelessRegulatoryDatabase = true;

  # This 30 GiB workstation benefits from zram before its 8 GiB NVMe swap
  # fallback.  The 50% logical device permits compression gains, while the
  # 25%-of-RAM resident cap preserves headroom for an interactive desktop and
  # lets the lower-priority physical swap absorb excess cold pages.
  zramSwap = {
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 5;
    swapDevices = 1;
  };
  services.zram-generator.settings.zram0.zram-resident-limit = "ram / 4";

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
