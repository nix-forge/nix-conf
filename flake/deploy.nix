{ inputs, self, ... }:
let
  inherit (inputs.nixpkgs) lib;
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  desktop = self.nixosConfigurations.desktop.config;
  desktopHome = desktop.home-manager.users.ianmh;
  macbookHome = self.homeConfigurations."ianmh@macbook-pro-m4".config;
  gamesMountPoint = "/home/ianmh/games";
  gamesDevice = "/dev/disk/by-uuid/f4595c1c-d701-45f2-b04a-d33e7ea0e8f6";
  hasHomePackage = name: lib.any (package: lib.getName package == name) desktopHome.home.packages;
  hasSystemPackage =
    name: lib.any (package: lib.getName package == name) desktop.environment.systemPackages;
  hasUdevPackage =
    name: lib.any (package: lib.getName package == name) desktop.services.udev.packages;
  hasMacbookHomePackage =
    name: lib.any (package: lib.getName package == name) macbookHome.home.packages;
  sharedUblockFilters = (import ../modules/shared/ublock-filter-lists.nix).customFilterLists;
  heliumPolicies =
    builtins.fromJSON
      desktop.environment.etc."chromium/policies/managed/helium-system.json".text;
  heliumUblockSettings =
    builtins.fromJSON
      heliumPolicies."3rdparty".extensions."blockjmkbacgjkknlgpkjjiijinjdanf".adminSettings;
  zenUblockSettings =
    desktopHome.programs.zen-browser.policies."3rdparty".Extensions."uBlock0@raymondhill.net".userSettings;
  zenImportedLists = builtins.elemAt (lib.findFirst (
    entry: builtins.elemAt entry 0 == "importedLists"
  ) null zenUblockSettings) 1;
  steamBigPicture = lib.findFirst (
    app: app.name == "Steam Big Picture"
  ) null desktop.services.sunshine.applications.apps;
in
{
  flake = {
    deploy.nodes.desktop = {
      hostname = "desktop";
      sshUser = "root";
      remoteBuild = true;
      activationTimeout = 600;
      confirmTimeout = 120;

      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.desktop;
      };
    };

    checks.x86_64-linux = inputs.deploy-rs.lib.x86_64-linux.deployChecks self.deploy // {
      desktop-configuration-contract =
        assert desktop.home-manager.users.ianmh.home.username == "ianmh";
        assert desktopHome.programs.zen-browser.enable;
        assert desktopHome.programs.helium.enable;
        assert desktopHome.wayland.windowManager.hyprland.enable;
        assert desktopHome.programs.fuzzel.enable;
        assert desktopHome.programs.fuzzel.settings.main."match-mode" == "fzf";
        assert lib.any (
          binding: lib.hasInfix "fuzzel" (builtins.toJSON binding)
        ) desktopHome.wayland.windowManager.hyprland.settings.bind;
        assert desktopHome.wayland.windowManager.hyprland.configType == "lua";
        assert desktopHome.wayland.windowManager.hyprland.extraConfig == "";
        assert desktopHome.home.pointerCursor.enable;
        assert desktopHome.home.pointerCursor.name == "Bibata-Modern-Ice";
        assert desktopHome.home.pointerCursor.size == 24;
        assert desktopHome.home.pointerCursor.gtk.enable;
        assert desktopHome.home.pointerCursor.x11.enable;
        assert
          (builtins.head desktopHome.wayland.windowManager.hyprland.settings.monitor).output == "SUNSHINE";
        assert
          (builtins.head desktopHome.wayland.windowManager.hyprland.settings.monitor).mode == "2560x1655@120";
        assert hasHomePackage "libreoffice";
        assert hasHomePackage "mpv-with-scripts";
        assert hasHomePackage "spotify";
        assert hasHomePackage "fuzzel";
        assert hasSystemPackage "dvgrab";
        assert hasSystemPackage "ffmpeg";
        assert hasSystemPackage "pciutils";
        assert hasSystemPackage "ghostty";
        assert hasSystemPackage "minidv-capture";
        assert hasSystemPackage "minidv-diagnose";
        assert hasSystemPackage "minidv-finalize";
        assert hasSystemPackage "minidv-transcode";
        assert hasSystemPackage "minidv-upscale";
        assert hasSystemPackage "minidv-verify";
        assert hasUdevPackage "minidv-firewire-udev-rules";
        assert lib.elem "https://nix-community.cachix.org" desktop.nix.settings.substituters;
        assert desktop.networking.nftables.enable;
        assert desktop.networking.firewall.enable;
        assert desktop.networking.firewall.backend == "nftables";
        assert desktop.networking.useNetworkd;
        assert !desktop.networking.useDHCP;
        assert !desktop.networking.networkmanager.enable;
        assert !(lib.elem 22 desktop.networking.firewall.allowedTCPPorts);
        assert lib.hasInfix "ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } tcp dport 22 accept"
          desktop.networking.firewall.extraInputRules;
        assert lib.hasInfix "ip6 saddr fc00::/7 tcp dport 22 accept"
          desktop.networking.firewall.extraInputRules;
        assert !desktop.services.openssh.openFirewall;
        assert !desktop.services.avahi.enable;
        assert desktop.services.resolved.enable;
        assert desktop.services.resolved.settings.Resolve.DNSSEC == "allow-downgrade";
        assert desktop.services.resolved.settings.Resolve.LLMNR == "false";
        assert desktop.services.resolved.settings.Resolve.MulticastDNS == "resolve";
        assert desktop.networking.wireless.iwd.enable;
        assert desktop.networking.wireless.iwd.settings.General.EnableNetworkConfiguration == false;
        assert desktop.networking.wireless.iwd.settings.General.AddressRandomization == "disabled";
        assert desktop.networking.wireless.iwd.settings.Settings.AutoConnect;
        assert desktop.networking.wireless.iwd.settings.DriverQuirks.PowerSaveDisable == "mt7921e";
        assert desktop.systemd.network.enable;
        assert !desktop.systemd.network.wait-online.enable;
        assert desktop.systemd.network.networks."30-wired-networks".dhcpV4Config.RouteMetric == 100;
        assert desktop.systemd.network.networks."30-wireless-networks".dhcpV4Config.RouteMetric == 600;
        assert desktop.systemd.network.networks."30-wired-networks".dhcpV4Config.UseDomains == "route";
        assert desktop.systemd.network.networks."30-wireless-networks".dhcpV4Config.UseDomains == "route";
        assert !desktop.systemd.network.networks."30-wired-networks".dhcpV4Config.SendHostname;
        assert !desktop.systemd.network.networks."30-wireless-networks".dhcpV4Config.SendHostname;
        assert !desktop.systemd.network.networks."30-wired-networks".ipv6AcceptRAConfig.UseRedirect;
        assert !desktop.systemd.network.networks."30-wireless-networks".ipv6AcceptRAConfig.UseRedirect;
        assert desktop.boot.kernel.sysctl."net.ipv4.conf.all.accept_redirects" == 0;
        assert desktop.boot.kernel.sysctl."net.ipv6.conf.all.accept_redirects" == 0;
        assert desktop.programs.nh.enable;
        assert desktop.boot.loader.systemd-boot.enable;
        assert desktop.boot.loader.systemd-boot.editor == false;
        assert desktop.boot.loader.systemd-boot.bootCounting.enable;
        assert desktop.boot.loader.systemd-boot.configurationLimit == 12;
        assert desktop.boot.initrd.systemd.enable;
        assert desktop.boot.initrd.systemd.emergencyAccess == false;
        assert desktop.boot.tmp.useTmpfs;
        assert desktop.hardware.cpu.amd.updateMicrocode;
        assert desktop.hardware.enableRedistributableFirmware;
        assert desktop.hardware.firmwareCompression == "zstd";
        assert desktop.services.fwupd.enable;
        assert
          desktop.services.fwupd.daemonSettings.EspLocation == desktop.boot.loader.efi.efiSysMountPoint;
        assert desktop.services.fwupd.uefiCapsuleSettings.RebootCleanup;
        assert desktop.services.fwupd.uefiCapsuleSettings.RequireESPFreeSpace == 128;
        assert lib.elem "timers.target" desktop.systemd.timers.fwupd-refresh.wantedBy;
        assert desktop.hardware.bluetooth.enable;
        assert desktop.hardware.bluetooth.powerOnBoot;
        assert desktop.hardware.bluetooth.disabledPlugins == [ "sap" ];
        assert desktop.hardware.bluetooth.settings.General.ControllerMode == "dual";
        assert desktop.hardware.bluetooth.settings.General.Privacy == "device";
        assert desktop.hardware.bluetooth.settings.General.PairableTimeout == 60;
        assert desktop.hardware.bluetooth.settings.General.JustWorksRepairing == "confirm";
        assert desktop.hardware.bluetooth.settings.General.SecureConnections == "on";
        assert desktop.hardware.bluetooth.settings.General.FastConnectable;
        assert desktop.hardware.bluetooth.settings.Policy.ResumeDelay == 3;
        assert desktop.hardware.bluetooth.input.General.ClassicBondedOnly;
        assert desktop.hardware.bluetooth.input.General.LEAutoSecurity;
        assert desktop.services.blueman.enable;
        assert
          desktop.services.pipewire.wireplumber.extraConfig."10-bluetooth-policy"."wireplumber.settings"."device.routes.mute-on-bluetooth-playback-removed";
        assert desktop.security.tpm2.enable;
        assert desktop.security.tpm2.applyUdevRules;
        assert desktop.security.tpm2.abrmd.enable;
        assert desktop.security.tpm2.tctiEnvironment.enable;
        assert desktop.security.tpm2.tctiEnvironment.interface == "tabrmd";
        assert desktop.security.tpm2.pkcs11.enable;
        assert lib.elem "tss" desktop.users.users.ianmh.extraGroups;
        assert desktop.console.earlySetup;
        assert desktop.console.useXkbConfig;
        assert desktop.services.getty.autologinUser == null;
        assert desktop.security.desktopKeyring.enable;
        assert desktop.services.gnome.gnome-keyring.enable;
        assert desktop.services.gnome.gcr-ssh-agent.enable;
        assert !desktop.programs.ssh.startAgent;
        assert !desktop.services.oo7.enable;
        assert desktop.security.wrappers.gnome-keyring-daemon.capabilities == "cap_ipc_lock=ep";
        assert desktop.security.pam.services.su.requireWheel;
        assert !desktop.security.pam.services.login.allowNullPassword;
        assert desktop.security.pam.services.login.failDelay.enable;
        assert desktop.security.pam.services.login.failDelay.delay == 3000000;
        assert desktop.security.pam.services.login.lastlog.enable;
        assert !desktop.security.pam.services.login.lastlog.silent;
        assert desktop.security.pam.services.login.enableGnomeKeyring;
        assert !desktop.security.pam.services.greetd.enableGnomeKeyring;
        assert !desktop.security.pam.services.login.gnupg.enable;
        assert desktop.security.pam.services.hyprlock.enable;
        assert desktop.security.pki.installCACerts;
        assert !desktop.security.pki.useCompatibleBundle;
        assert desktop.security.pki.certificateFiles == [ ];
        assert desktop.security.pki.certificates == [ ];
        assert desktop.security.pki.caCertificateBlacklist == [ ];
        assert lib.hasInfix "/etc/ssl/certs/ca-bundle.crt" (toString desktop.security.pki.caBundle);
        assert
          desktop.environment.etc."ssl/certs/ca-certificates.crt".source == desktop.security.pki.caBundle;
        assert desktop.environment.etc."ssl/trust-source".source != null;
        assert desktop.security.polkit.enable;
        assert !desktop.security.polkit.enablePkexecWrapper;
        assert desktop.security.polkit.adminIdentities == [ "unix-group:wheel" ];
        assert desktop.security.polkit.settings.Polkitd.ExpirationSeconds == 300;
        assert
          desktop.security.polkit.extraArgs == [
            "--no-debug"
            "--log-level=notice"
          ];
        assert !lib.hasInfix "polkit.log(" desktop.security.polkit.extraConfig;
        assert lib.hasInfix "org.freedesktop.fwupd.get-remotes" desktop.security.polkit.extraConfig;
        assert lib.hasInfix "subject.user == \"fwupd-refresh\"" desktop.security.polkit.extraConfig;
        assert lib.hasInfix "polkit-gnome-authentication-agent-1" (
          toString desktop.systemd.user.services.polkit-gnome-authentication-agent-1.serviceConfig.ExecStart
        );
        assert
          desktop.systemd.user.services.polkit-gnome-authentication-agent-1.serviceConfig.Restart
          == "on-failure";
        assert desktop.security.sudo.enable;
        assert desktop.security.sudo.wheelNeedsPassword;
        assert desktop.security.sudo.execWheelOnly;
        assert desktop.security.sudo.defaultOptions == [ "NOSETENV" ];
        assert !lib.hasInfix "NOPASSWD" desktop.security.sudo.configFile;
        assert lib.hasInfix "Defaults use_pty" desktop.security.sudo.configFile;
        assert lib.hasInfix "Defaults timestamp_type=tty" desktop.security.sudo.configFile;
        assert lib.hasInfix "Defaults timestamp_timeout=5" desktop.security.sudo.configFile;
        assert lib.hasInfix "Defaults !pwfeedback" desktop.security.sudo.configFile;
        assert desktop.security.wrappers.sudo.group == "wheel";
        assert desktop.security.wrappers.sudo.setuid;
        assert desktop.security.wrappers.sudo.permissions == "u+rx,g+x";
        assert !desktop.security.pam.sshAgentAuth.enable;
        assert !desktop.security.pam.ussh.enable;
        assert !desktop.security.pam.services.sudo.sshAgentAuth;
        assert !desktop.security.pam.services.sudo.usshAuth;
        assert desktop.security.appArmorBaseline.enable;
        assert desktop.security.apparmor.enable;
        assert !desktop.security.apparmor.enableCache;
        assert !desktop.security.apparmor.killUnconfinedConfinables;
        assert desktop.security.apparmor.policies == { };
        assert lib.elem "apparmor" desktop.security.lsm;
        assert lib.elem "apparmor=1" desktop.boot.kernelParams;
        assert lib.length (lib.filter (param: lib.hasPrefix "lsm=" param) desktop.boot.kernelParams) == 1;
        assert
          lib.length (lib.filter (param: lib.hasPrefix "loglevel=" param) desktop.boot.kernelParams) == 1;
        assert desktop.boot.consoleLogLevel == 3;
        assert desktop.systemd.services.apparmor.unitConfig.ConditionSecurity == "apparmor";
        assert desktop.security.clamav.enable;
        assert desktop.services.clamav.daemon.enable;
        assert desktop.services.clamav.updater.enable;
        assert desktop.services.clamav.scanner.enable;
        assert desktop.services.clamav.clamonacc.enable;
        assert !desktop.services.clamav.fangfrisch.enable;
        assert desktop.services.clamav.updater.frequency == 6;
        assert desktop.services.clamav.updater.interval == "*-*-* 00/4:00:00";
        assert desktop.services.clamav.daemon.settings.LocalSocketMode == "660";
        assert desktop.services.clamav.daemon.settings.MaxThreads == 4;
        assert desktop.services.clamav.daemon.settings.MaxQueue == 8;
        assert desktop.services.clamav.daemon.settings.OnAccessPrevention;
        assert desktop.services.clamav.daemon.settings.OnAccessExtraScanning;
        assert desktop.services.clamav.daemon.settings.OnAccessIncludePath == [ "/home/ianmh/Downloads" ];
        assert desktop.services.clamav.scanner.interval == "Sun *-*-* 03:30:00";
        assert
          desktop.services.clamav.scanner.scanDirectories == [
            "/home/ianmh/Downloads"
            "/home/ianmh/Desktop"
            "/home/ianmh/Documents"
            "/home/ianmh/Projects"
          ];
        assert desktop.systemd.timers.clamav-freshclam.timerConfig.Persistent;
        assert desktop.systemd.timers.clamav-freshclam.timerConfig.RandomizedDelaySec == "30m";
        assert desktop.systemd.timers.clamdscan.timerConfig.Persistent;
        assert desktop.systemd.timers.clamdscan.timerConfig.RandomizedDelaySec == "2h";
        assert desktop.systemd.services.clamdscan.serviceConfig.Nice == 19;
        assert desktop.systemd.services.clamdscan.serviceConfig.IOSchedulingClass == "idle";
        assert desktop.security.usbguardBaseline.enable;
        assert desktop.services.usbguard.enable;
        assert desktop.services.usbguard.implicitPolicyTarget == "block";
        assert desktop.services.usbguard.presentDevicePolicy == "apply-policy";
        assert desktop.services.usbguard.presentControllerPolicy == "keep";
        assert desktop.services.usbguard.insertedDevicePolicy == "apply-policy";
        assert !desktop.services.usbguard.restoreControllerDeviceState;
        assert desktop.services.usbguard.deviceRulesWithPort;
        assert desktop.services.usbguard.IPCAllowedUsers == [ "root" ];
        assert desktop.services.usbguard.IPCAllowedGroups == [ ];
        assert !desktop.services.usbguard.dbus.enable;
        assert lib.hasInfix "allow hash \"kL7WFVC+wRu2UhoA7qb7Ga7AhIMyAuHfB4xoYj5eFDA=\""
          desktop.services.usbguard.rules;
        assert !lib.hasInfix "090c:1000" desktop.services.usbguard.rules;
        assert desktop.security.allowUserNamespaces;
        assert desktop.security.virtualisation.flushL1DataCache == null;
        assert
          !lib.any (param: lib.hasPrefix "kvm-intel.vmentry_l1d_flush=" param) desktop.boot.kernelParams;
        assert !desktop.virtualisation.libvirtd.enable;
        assert !desktop.virtualisation.docker.enable;
        assert desktop.virtualisation.docker.rootless.enable;
        assert desktop.virtualisation.docker.rootless.daemon.settings."live-restore";
        assert desktop.virtualisation.docker.rootless.daemon.settings."log-driver" == "local";
        assert desktop.virtualisation.docker.rootless.daemon.settings."log-opts"."max-size" == "10m";
        assert desktop.virtualisation.docker.rootless.daemon.settings."log-opts"."max-file" == "3";
        assert !(desktop.users.groups ? docker);
        assert !desktop.i18n.imperativeLocale;
        assert desktop.i18n.defaultLocale == "en_US.UTF-8";
        assert desktop.time.timeZone == "America/Los_Angeles";
        assert !desktop.time.hardwareClockInLocalTime;
        assert desktop.services.chrony.enable;
        assert desktop.services.chrony.enableNTS;
        assert
          desktop.services.chrony.servers == [
            "time.cloudflare.com"
            "nts.netnod.se"
          ];
        assert desktop.services.chrony.serverOption == "iburst";
        assert desktop.services.chrony.enableMemoryLocking;
        assert desktop.services.chrony.enableRTCTrimming;
        assert desktop.services.chrony.makestep.enable;
        assert desktop.services.chrony.makestep.threshold == 0.1;
        assert desktop.services.chrony.makestep.limit == 3;
        assert lib.hasInfix "cmdport 0" desktop.services.chrony.extraConfig;
        assert !desktop.services.chrony.dispatcherScript;
        assert !desktop.services.timesyncd.enable;
        assert lib.all (module: lib.elem module desktop.boot.initrd.kernelModules) [
          "nvme"
          "btrfs"
        ];
        assert desktop.boot.initrd.supportedFilesystems == { btrfs = true; };
        assert desktop.services.telegraf.enable;
        assert desktop.services.telegraf.extraConfig.outputs.prometheus_client.listen == "127.0.0.1:9273";
        assert desktop.security.wrappers.smartctl-telegraf.owner == "telegraf";
        assert desktop.services.fstrim.enable;
        assert desktop.services.fstrim.interval == "weekly";
        assert desktop.systemd.services.fstrim.unitConfig.ConditionACPower;
        assert desktop.systemd.services.fstrim.serviceConfig.Nice == 19;
        assert desktop.systemd.services.fstrim.serviceConfig.IOSchedulingClass == "idle";
        assert desktop.systemd.timers.fstrim.timerConfig.AccuracySec == "1h";
        assert desktop.systemd.timers.fstrim.timerConfig.Persistent;
        assert desktop.systemd.timers.fstrim.timerConfig.RandomizedDelaySec == "2h";
        assert desktop.zramSwap.enable;
        assert desktop.zramSwap.algorithm == "zstd";
        assert desktop.zramSwap.swapDevices == 1;
        assert desktop.zramSwap.memoryPercent == 50;
        assert desktop.zramSwap.priority == 5;
        assert desktop.zramSwap.writebackDevice == null;
        assert !desktop.boot.zswap.enable;
        assert desktop.systemd.oomd.enable;
        assert !desktop.systemd.oomd.enableRootSlice;
        assert !desktop.systemd.oomd.enableSystemSlice;
        assert !desktop.systemd.oomd.enableUserSlices;
        assert desktop.services.zram-generator.settings.zram0."compression-algorithm" == "zstd";
        assert desktop.services.zram-generator.settings.zram0."swap-priority" == 5;
        assert desktop.services.zram-generator.settings.zram0."zram-size" == "50 / 100 * ram";
        assert desktop.services.zram-generator.settings.zram0."zram-resident-limit" == "ram / 4";
        assert desktop.services.gvfs.enable;
        assert desktop.services.tumbler.enable;
        assert desktop.services.udisks2.enable;
        assert !desktop.services.udisks2.mountOnMedia;
        assert desktop.services.udisks2.settings."udisks2.conf".defaults.encryption == "luks2";
        assert desktop.services.udisks2.settings."udisks2.conf".udisks2.modules == [ "*" ];
        assert
          desktop.services.udisks2.settings."udisks2.conf".udisks2.modules_load_preference == "ondemand";
        assert desktop.services.openssh.settings.X11Forwarding == false;
        assert desktop.services.openssh.settings.UseDns == false;
        assert desktop.services.openssh.settings.StreamLocalBindUnlink == true;
        assert builtins.hasAttr "updateDiff" desktop.system.preSwitchChecks;
        assert builtins.hasAttr "expectedHostname" desktop.system.preSwitchChecks;
        assert desktop.programs.gamemode.enable;
        assert desktop.programs.gamemode.enableRenice;
        assert desktop.programs.gamemode.settings.general.softrealtime == "off";
        assert desktop.programs.gamemode.settings.general.renice == 10;
        assert desktop.programs.gamescope.enable;
        assert !desktop.programs.gamescope.capSysNice;
        assert desktop.programs.steam.enable;
        assert desktop.programs.steam.gamescopeSession.enable;
        assert desktop.programs.steam.extest.enable;
        assert desktop.programs.steam.protontricks.enable;
        assert desktop.hardware.graphics.enable32Bit;
        assert desktop.services.pipewire.enable;
        assert desktop.services.pipewire.audio.enable;
        assert desktop.services.pipewire.alsa.support32Bit;
        assert desktop.services.pipewire.pulse.enable;
        assert desktop.services.pipewire.jack.enable;
        assert desktop.services.pipewire.wireplumber.enable;
        assert desktop.security.rtkit.enable;
        assert !desktop.services.pulseaudio.enable;
        assert !lib.any (limit: limit.domain == "@audio") desktop.security.pam.loginLimits;
        assert
          desktop.services.pipewire.extraConfig.pipewire."90-desktop-low-latency"."context.properties"."default.clock.quantum"
          == 128;
        assert
          desktop.services.pipewire.extraConfig.pipewire-pulse."90-desktop-low-latency"."pulse.properties"."pulse.default.tlength"
          == "256/48000";
        assert desktop.fileSystems.${gamesMountPoint}.device == gamesDevice;
        assert desktop.fileSystems.${gamesMountPoint}.fsType == "btrfs";
        assert lib.all (option: lib.elem option desktop.fileSystems.${gamesMountPoint}.options) [
          "subvol=games"
          "compress=zstd:1"
          "noatime"
          "nofail"
          "x-systemd.device-timeout=10s"
        ];
        assert !lib.elem "discard=async" desktop.fileSystems.${gamesMountPoint}.options;
        assert desktop.services.btrfs.autoScrub.enable;
        assert lib.elem gamesMountPoint desktop.services.btrfs.autoScrub.fileSystems;
        assert desktop.services.btrfs.autoScrub.interval == "Sun *-*-01..07 03:00:00";
        assert desktop.services.btrfs.autoScrub.limit == "800M";
        assert desktop.systemd.timers."btrfs-scrub--".timerConfig.AccuracySec == "1h";
        assert desktop.systemd.timers."btrfs-scrub--".timerConfig.RandomizedDelaySec == "2h";
        assert desktop.systemd.timers."btrfs-scrub-home-ianmh-games".timerConfig.AccuracySec == "1h";
        assert desktop.systemd.timers."btrfs-scrub-home-ianmh-games".timerConfig.RandomizedDelaySec == "2h";
        assert desktop.services.sunshine.enable;
        assert desktop.services.sunshine.autoStart;
        assert !desktop.services.sunshine.openFirewall;
        assert !desktop.services.sunshine.capSysAdmin;
        assert desktop.systemd.user.services.sunshine.unitConfig.ConditionUser == "ianmh";
        assert desktop.services.sunshine.settings.encoder == "nvenc";
        assert desktop.services.sunshine.settings.max_bitrate == 60000;
        assert desktop.services.sunshine.settings.av1_mode == 3;
        assert desktop.services.sunshine.settings.adapter_name == "/dev/dri/renderD129";
        assert desktop.services.sunshine.settings.capture == "wlr";
        assert desktop.services.sunshine.settings.upnp == "disabled";
        assert
          desktop.services.sunshine.settings.csrf_allowed_origins
          == "https://desktop:47990,https://desktop.local:47990,https://192.168.10.178:47990";
        assert desktop.services.sunshine.settings.lan_encryption_mode == 2;
        assert steamBigPicture != null;
        assert
          steamBigPicture.detached
          == [ "${lib.getExe desktop.programs.steam.package} steam://open/bigpicture" ];
        assert !(builtins.hasAttr "prep-cmd" steamBigPicture);
        assert desktop.programs.hyprland.enable;
        assert desktop.programs.hyprland.withUWSM;
        assert desktop.programs.uwsm.enable;
        assert desktop.services.greetd.enable;
        assert !desktop.services.displayManager.gdm.enable;
        assert desktop.services.greetd.settings.initial_session.user == "ianmh";
        assert desktop.systemd.user.services.sunshine-headless-output.unitConfig.ConditionUser == "ianmh";
        assert lib.elem "sunshine-headless-output.service"
          desktop.systemd.user.services.sunshine.unitConfig.Wants;
        assert desktop.systemd.user.services.sunshine.serviceConfig.Restart == "on-failure";
        assert desktop.systemd.user.services.sunshine.serviceConfig.RestartSec == "5s";
        assert
          desktop.systemd.user.services.sunshine-headless-output.serviceConfig.TimeoutStartSec == "150s";
        assert desktop.hardware.uinput.enable;
        assert lib.elem "uinput" desktop.users.users.ianmh.extraGroups;
        assert lib.hasInfix "tcp dport { 47984, 47989, 47990, 48010 } accept"
          desktop.networking.firewall.extraInputRules;
        assert lib.hasInfix "udp dport { 47998, 47999, 48000, 48002, 48010 } accept"
          desktop.networking.firewall.extraInputRules;
        assert hasMacbookHomePackage "moonlight-qt";
        assert lib.hasInfix "width -int 2560" macbookHome.home.activation.configureMoonlightStreaming.data;
        assert lib.hasInfix "height -int 1655" macbookHome.home.activation.configureMoonlightStreaming.data;
        assert lib.hasInfix "fps -int 120" macbookHome.home.activation.configureMoonlightStreaming.data;
        assert lib.hasInfix "bitrate -int 55000"
          macbookHome.home.activation.configureMoonlightStreaming.data;
        assert lib.hasInfix "videocfg -int 4" macbookHome.home.activation.configureMoonlightStreaming.data;
        assert lib.hasInfix "hdr -bool false" macbookHome.home.activation.configureMoonlightStreaming.data;
        assert !desktop.virtualisation.docker.enable;
        assert desktop.virtualisation.docker.rootless.enable;
        assert desktop.users.users.ianmh.linger;
        assert !(desktop.systemd.services ? docker);
        assert desktop.systemd.user.services.docker.unitConfig.ConditionUser == "ianmh";
        assert desktopHome.programs.ssh.settings."nid??????".data.StrictHostKeyChecking == "accept-new";
        assert desktopHome.nixSeal.enable;
        assert builtins.hasAttr "nix-access-tokens" desktopHome.nixSeal.secrets;
        assert desktop.nixSeal.enable;
        assert desktop.nixSeal.linux.volatileRuntime.enable;
        assert desktop.users.groups ? ianmh;
        assert lib.elem "ianmh" desktop.users.users.ianmh.extraGroups;
        assert
          desktop.nixSeal.secrets."nix-access-tokens".source
          == "secrets/ianhollow/users/ianmh/nix-access-tokens.age";
        assert desktop.fileSystems."/run/nix-seal".fsType == "tmpfs";
        assert lib.elem "noswap" desktop.fileSystems."/run/nix-seal".options;
        assert lib.hasInfix "/bin/mount -- /run/nix-seal"
          desktop.system.activationScripts.nixSealRuntime.text;
        assert desktop.systemd.services.nix-seal-runtime.serviceConfig.RequiresMountsFor == "/run/nix-seal";
        assert lib.hasInfix "/run/nix-seal/users/ianmh" desktopHome.home.activation.nixSeal.data;
        assert !lib.hasInfix "XDG_RUNTIME_DIR is required" desktopHome.home.activation.nixSeal.data;
        assert heliumUblockSettings.userSettings.importedLists == sharedUblockFilters;
        assert zenImportedLists == sharedUblockFilters;
        pkgs.runCommand "desktop-configuration-contract" { } "touch $out";
    };
  };
}
