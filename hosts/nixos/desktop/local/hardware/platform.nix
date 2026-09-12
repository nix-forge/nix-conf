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
  # This board uses USB audio; its Ryzen HD Audio controller has no codecs. Exclude
  # only that verified PCI function before another HD Audio device loads the shared
  # driver. HDMI and USB audio retain their normal drivers and PCM devices.
  boot.initrd.systemd.services.disable-empty-audio-controller = {
    description = "Exclude the unused onboard HD Audio controller";
    wantedBy = [ "sysinit.target" ];
    before = [
      "systemd-modules-load.service"
      "systemd-udev-trigger.service"
      "systemd-udevd.service"
    ];
    unitConfig.DefaultDependencies = false;
    serviceConfig.Type = "oneshot";
    script = ''
      device=/sys/bus/pci/devices/0000:11:00.6
      if [[ -d "$device" &&
        "$(<"$device/vendor")" == 0x1022 &&
        "$(<"$device/device")" == 0x15e3 &&
        "$(<"$device/subsystem_vendor")" == 0x1462 &&
        "$(<"$device/subsystem_device")" == 0xed75 ]]; then
        printf '%s\n' none > "$device/driver_override"
      fi
    '';
  };
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
  boot.extraModprobeConfig = lib.concatLines [
    "options kvm_amd nested=1"
    # The onboard USB audio device can time out during sample-rate discovery.
    # Probe it asynchronously so this module load can return before the slow
    # control requests finish. Audio discovery still runs to completion; check
    # boot timing and named playback/capture devices after the next reboot.
    "options snd_usb_audio async_probe=1"
    # The board's Nuvoton NCT6687D-R needs force=1 with nct6683 on non-Intel boards.
    "options nct6683 force=1"
    "options cfg80211 ieee80211_regdom=US"
  ];

  # Zen 4 receives vendor microcode through the initrd before the kernel
  # starts normal userspace. Keep this explicit for this AMD physical host;
  # it must not depend on a shared firmware-policy default.
  hardware.cpu.amd.updateMicrocode = true;
  hardware.wirelessRegulatoryDatabase = true;

  # This 30 GiB workstation benefits from zram before its 8 GiB NVMe swap
  # fallback. The 50% logical capacity permits compression gains and bounds
  # worst-case storage. Do not impose a smaller resident cap: failed writes
  # at that cap do not transparently spill into lower-priority disk swap.
  zramSwap = {
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 5;
    swapDevices = 1;
  };

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
