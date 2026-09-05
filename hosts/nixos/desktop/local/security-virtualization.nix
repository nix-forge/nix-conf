{
  # This is an on-demand Nix build fallback, not a resident ARM VM. The kernel
  # starts QEMU user-mode translation only when an aarch64-linux executable is
  # invoked. Native ARM builds should still use the M4 when practical.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  security = {
    # Rootless Docker needs unprivileged user namespaces.  Keep that kernel
    # facility available for this workstation's container workload, while
    # retaining the rootless daemon instead of creating a root-equivalent
    # `docker` group or system socket.
    allowUserNamespaces = true;

    virtualisation.flushL1DataCache = null;
  };

  virtualisation.libvirtWorkstation = {
    enable = true;
    operators = [ "ianmh" ];

    # Full-system AArch64 emulation is unnecessary for package builds. Keep
    # libvirt on the native KVM-only QEMU package.
    emulateAarch64 = false;

    # Keep a stable host-only management path separate from optional egress.
    # Neither subnet overlaps the desktop's current 192.168.10.0/24 LAN.
    networks = {
      dev-mgmt = {
        mode = "isolated";
        bridge = "virbr-mgmt";
        ipv4Prefix = "192.168.123";
        domain = "mgmt.vm.internal";
        reservations = {
          windows-runtime = {
            macAddress = "52:54:00:12:30:12";
            address = 12;
          };
        };
      };

      dev-nat = {
        mode = "nat";
        bridge = "virbr-nat";
        # Avoid libvirt's conventional 192.168.122.0/24 default network so a
        # stale or manually created `default` network cannot collide.
        ipv4Prefix = "192.168.124";
        domain = "egress.vm.internal";
        reservations = {
          windows-runtime = {
            macAddress = "52:54:00:12:20:12";
            address = 12;
          };
        };
      };
    };

    # This host stores VM images on Btrfs. New files inherit NOCOW to avoid
    # double copy-on-write; existing images still need an individual audit.
    storage.nocow = true;

    windowsVm = {
      enable = true;
      name = "windows-runtime";
      uuid = "656e7db9-a2d6-45f1-8e79-76ba6cdc12e8";
      generationId = "043d16f9-01bf-42e0-9395-0f407ee5896c";
      computerName = "WIN-RUNTIME";
      diskSerial = "WINRUNTIME001";
      machine = "pc-q35-10.2";

      # Manual start is the workstation policy. Change this only after cold
      # boot, Windows Update reboot, and recovery tests pass in server mode.
      autostart = false;
      networks = [
        "dev-mgmt"
        "dev-nat"
      ];
      managementNetwork = "dev-mgmt";

      administrator = {
        name = "vmadmin";
        # This is an explicit accepted risk for the persistent live runtime.
        # Hypervisor and network controls remain in force outside the guest.
        disableUac = true;
      };

      baseline = {
        # Keep the Windows shell usable for emergency debugging, but stop UI,
        # browser, gaming, and suggestion processes that add no value to the
        # unattended runtime. Security, update, Store, and WebView stay intact.
        profile = "headless-runtime";
        removeAppxPackages = [
          "Clipchamp.Clipchamp"
          "Microsoft.BingNews"
          "Microsoft.BingWeather"
          "Microsoft.Copilot"
          "Microsoft.GamingApp"
          "Microsoft.GetHelp"
          "Microsoft.Getstarted"
          "Microsoft.MicrosoftOfficeHub"
          "Microsoft.MicrosoftSolitaireCollection"
          "Microsoft.OutlookForWindows"
          "Microsoft.People"
          "Microsoft.PowerAutomateDesktop"
          "Microsoft.Windows.Ai.Copilot.Provider"
          "Microsoft.Windows.DevHome"
          "Microsoft.WindowsFeedbackHub"
          "Microsoft.Xbox.TCUI"
          "Microsoft.XboxApp"
          "Microsoft.XboxGameOverlay"
          "Microsoft.XboxGamingOverlay"
          "Microsoft.XboxIdentityProvider"
          "Microsoft.XboxSpeechToTextOverlay"
          "Microsoft.YourPhone"
          "Microsoft.ZuneMusic"
          "Microsoft.ZuneVideo"
          "MicrosoftCorporationII.MicrosoftFamily"
          "MicrosoftTeams"
          "MSTeams"
        ];
      };

      installation = {
        # Microsoft's public production ISO is multi-edition. Its generated
        # CDN URL expires after 24 hours, so the stable declaration is the
        # release, filename, Microsoft-published hash, and retained local
        # artifact. The exact WIM label selects Pro without embedding a key.
        release = "25H2";
        mediaDescription = "Windows 11 25H2 multi-edition x64, English (United States)";
        downloadPage = "https://www.microsoft.com/en-us/software-download/windows11";
        imageName = "Windows 11 Pro";
        editionId = "Professional";
        isoFileName = "Win11_25H2_English_x64_v2.iso";
        isoSha256 = "768984706B909479417B2368438909440F2967FF05C6A9195ED2667254E465E3";
        locale = "en-US";
        timeZone = "Pacific Standard Time";
      };

      resources = {
        # vCPUs are scheduler-visible capacity, not reserved host cores. The
        # lower share weight makes a busy guest yield to interactive host work.
        vcpus = 4;
        memoryMiB = 8192;
        diskSizeGiB = 128;
        cpuShares = 512;
      };

      maintenance = {
        activeHoursStart = 5;
        activeHoursEnd = 23;
      };
    };

    # Do not install the privileged SPICE USB helper until a guest needs a
    # specific device and the host's USBGuard policy has been reviewed.
    usbRedirection.enable = false;

    # The AMD IOMMU is active, but GPU passthrough remains a separate rebooting
    # change. A read-only audit found only these two functions in group 12.
    # Recheck them after firmware or hardware changes, prove the iGPU-only
    # desktop first, and verify FireWire with the unchanged IOMMU mode. Never
    # add an ACS override or unsafe interrupts to make a poor group appear safe.
    vfio = {
      enable = false;
      specialisationName = "windows-vfio";
      hostVideoDrivers = [ "amdgpu" ];
      hostInitrdModules = [ "amdgpu" ];
      blacklistedModules = [
        "nouveau"
        "nvidia"
        "nvidia_drm"
        "nvidia_modeset"
        "nvidia_uvm"
      ];
      disableSunshine = true;

      devices = {
        rtx4070 = {
          pciAddress = "0000:01:00.0";
          vendorDeviceId = "10de:2786";
          iommuGroup = 12;
        };

        rtx4070-audio = {
          pciAddress = "0000:01:00.1";
          vendorDeviceId = "10de:22bc";
          iommuGroup = 12;
        };
      };
    };
  };

  # Rootless Docker can enforce CPU, cpuset, I/O, memory, and PID limits only
  # when the user manager receives those cgroup-v2 controllers. This is a
  # host-wide resource-policy decision, so it belongs in this local module.
  systemd.services."user@".serviceConfig.Delegate = "cpu cpuset io memory pids";
}
