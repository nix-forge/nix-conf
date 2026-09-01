{ inputs, self, ... }:
let
  inherit (inputs.nixpkgs) lib;
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  desktop = self.nixosConfigurations.desktop.config;
  # This installer-only system keeps the Disko layout under the same flake
  # evaluation contract as the deployed host, without importing it into the
  # running desktop configuration or touching any disk during checks.
  desktopDisko = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs.inputs = inputs;
    modules = [
      ../modules/nixos/hardware/storage.nix
      ../hosts/nixos/desktop/local/hardware/filesystems.nix
      ../hosts/nixos/desktop/disko-system.nix
    ];
  };
  desktopHome = desktop.home-manager.users.ianmh;
  macbook = self.darwinConfigurations.macbook-pro-m4.config;
  macbookHome = macbook.home-manager.users.ianmh;
  hasHomePackage = name: lib.any (package: lib.getName package == name) desktopHome.home.packages;
  hasSystemPackage =
    name: lib.any (package: lib.getName package == name) desktop.environment.systemPackages;
  hasUdevPackage =
    name: lib.any (package: lib.getName package == name) desktop.services.udev.packages;
  hasMacbookHomePackage =
    name: lib.any (package: lib.getName package == name) macbookHome.home.packages;
  sharedUblockFilters = desktop.programs.chromiumPolicies.customFilterLists;
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
        # Determinate owns the daemon and garbage collector on every system.
        # Keep its evaluation features on, its GC unshared, and Home Manager
        # from placing an upstream Nix on the user's PATH.
        assert desktop.determinate.enable;
        assert desktop.nix.settings.lazy-trees;
        assert desktop.nix.settings.eval-cores == 0;
        assert desktop.nix.settings.flake-registry == "";
        assert
          builtins.attrNames desktop.nix.registry == [
            "nixpkgs"
            "self"
          ];
        assert desktop.nix.registry.nixpkgs.exact;
        assert !desktop.nix.gc.automatic;
        assert lib.elem "nodiscard" desktop.fileSystems."/nix".options;
        assert lib.elem "${pkgs.util-linux}/bin/fstrim --all --minimum 1M"
          desktop.systemd.services.fstrim.serviceConfig.ExecStart;
        assert
          (builtins.fromJSON desktop.environment.etc."determinate/config.json".text).garbageCollector.strategy
          == "automatic";
        assert macbook.determinateNix.enable;
        assert !macbook.nix.enable;
        assert macbook.determinateNix.customSettings.lazy-trees;
        assert macbook.determinateNix.customSettings.eval-cores == 0;
        assert macbook.determinateNix.customSettings.flake-registry == "/etc/nix/registry.json";
        assert
          builtins.attrNames macbook.determinateNix.registry == [
            "nixpkgs"
            "self"
          ];
        assert macbook.determinateNix.registry.nixpkgs.exact;
        assert macbook.determinateNix.determinateNixd.garbageCollector.strategy == "automatic";
        assert macbook.determinateNix.determinateNixd.builder.state == "enabled";
        assert desktopHome.nix.package == null;
        assert macbookHome.nix.package == null;
        # Both profiles depend on an OS-managed nix-seal runtime and are
        # intentionally unavailable as weaker standalone Home Manager outputs.
        assert !(builtins.hasAttr "ianmh@desktop" self.homeConfigurations);
        assert !(builtins.hasAttr "ianmh@macbook-pro-m4" self.homeConfigurations);
        assert desktopHome.programs.zen-browser.enable;
        assert desktopHome.programs.helium.enable;
        assert desktopHome.wayland.windowManager.hyprland.enable;
        assert desktopHome.programs.fuzzel.enable;
        assert desktopHome.programs.fuzzel.settings.main."match-mode" == "fzf";
        assert desktopHome.desktop.enable;
        assert desktop.desktop.system.enable;
        assert desktop.programs.dconf.enable;
        assert desktop.services.upower.enable;
        assert desktop.services.power-profiles-daemon.enable;
        assert desktop.programs.thunar.enable;
        assert desktopHome.programs.waybar.enable;
        assert desktopHome.programs.waybar.settings.mainBar.network."on-click" == "iwgtk";
        assert desktopHome.desktop.applications.networkBackend == "iwd";
        assert desktopHome.desktop.clipboard.wipeOnLock;
        assert desktopHome.desktop.wallpaper.enable;
        assert desktopHome.desktop.wallpaper.mode == "rotate";
        assert desktopHome.desktop.wallpaper.sources.nasaSvs.enable;
        assert desktopHome.desktop.wallpaper.sources.nasaSvs.maxCandidatePages == 5;
        assert desktopHome.desktop.wallpaper.sources.clevelandMuseum.enable;
        assert desktopHome.desktop.wallpaper.sources.clevelandMuseum.maxFileSizeMiB == 60;
        assert desktopHome.desktop.wallpaper.sources.clevelandMuseum.maxImages == 20;
        assert desktopHome.desktop.wallpaper.rotation.interval == "30min";
        assert builtins.hasAttr "swaync" desktopHome.systemd.user.services;
        assert builtins.hasAttr "swayosd" desktopHome.systemd.user.services;
        assert builtins.hasAttr "cliphist" desktopHome.systemd.user.services;
        assert builtins.hasAttr "awww" desktopHome.systemd.user.services;
        assert builtins.hasAttr "desktop-wallpaper-rotate" desktopHome.systemd.user.services;
        assert builtins.hasAttr "desktop-wallpaper-fetch-nasa" desktopHome.systemd.user.services;
        assert builtins.hasAttr "desktop-wallpaper-fetch-cma" desktopHome.systemd.user.services;
        assert builtins.hasAttr "desktop-wallpaper-rotate" desktopHome.systemd.user.timers;
        assert builtins.hasAttr "desktop-wallpaper-fetch-nasa" desktopHome.systemd.user.timers;
        assert builtins.hasAttr "desktop-wallpaper-fetch-cma" desktopHome.systemd.user.timers;
        assert builtins.hasAttr "desktop-wallpaper-fetch-nasa-bootstrap" desktopHome.systemd.user.timers;
        assert builtins.hasAttr "desktop-wallpaper-fetch-cma-bootstrap" desktopHome.systemd.user.timers;
        assert
          desktopHome.systemd.user.timers.desktop-wallpaper-fetch-nasa-bootstrap.Timer.Unit
          == "desktop-wallpaper-fetch-nasa.service";
        assert
          desktopHome.systemd.user.timers.desktop-wallpaper-fetch-cma-bootstrap.Timer.Unit
          == "desktop-wallpaper-fetch-cma.service";
        # NixOS's Hyprlock module owns the packaged Hypridle service. Home
        # Manager supplies only its configuration and must not shadow it.
        assert desktop.services.hypridle.enable;
        assert !(builtins.hasAttr "hypridle" desktopHome.systemd.user.services);
        assert hasHomePackage "obs-studio";
        assert hasHomePackage "satty";
        assert hasHomePackage "cliphist";
        assert hasHomePackage "desktop-wallpaper-next";
        assert hasHomePackage "desktop-wallpaper-fetch-nasa";
        assert hasHomePackage "desktop-wallpaper-fetch-cma";
        assert !(hasHomePackage "desktop-wallpaper-source");
        assert lib.any (
          binding: lib.hasInfix "fuzzel" (builtins.toJSON binding)
        ) desktopHome.wayland.windowManager.hyprland.settings.bind;
        assert lib.any (
          binding: lib.hasInfix "swayosd-client" (builtins.toJSON binding)
        ) desktopHome.wayland.windowManager.hyprland.settings.bind;
        assert lib.any (
          binding: lib.hasInfix "desktop-screenshot" (builtins.toJSON binding)
        ) desktopHome.wayland.windowManager.hyprland.settings.bind;
        assert lib.any (
          binding: lib.hasInfix "desktop-wallpaper-next" (builtins.toJSON binding)
        ) desktopHome.wayland.windowManager.hyprland.settings.bind;
        assert desktopHome.wayland.windowManager.hyprland.configType == "lua";
        assert desktopHome.wayland.windowManager.hyprland.extraConfig == "";
        # Lua-mode Home Manager currently renders legacy `KEY,VALUE` env
        # entries as one argument to `hl.env`.  UWSM owns this session, so
        # cursor settings must stay in its environment file instead.
        assert (desktopHome.wayland.windowManager.hyprland.settings.env or [ ]) == [ ];
        assert desktopHome.home.pointerCursor.enable;
        assert desktopHome.home.pointerCursor.name == "Bibata-Modern-Ice";
        assert desktopHome.home.pointerCursor.size == 24;
        assert desktopHome.home.pointerCursor.gtk.enable;
        assert desktopHome.home.pointerCursor.x11.enable;
        assert desktopHome.wayland.windowManager.hyprland.displayScaling.enable;
        assert desktopHome.wayland.windowManager.hyprland.displayScaling.cursor.enable;
        assert desktopHome.wayland.windowManager.hyprland.displayScaling.cursor.logicalSize == 16;
        assert desktopHome.wayland.windowManager.hyprland.displayScaling.cursor.resolvedSize == 24;
        assert desktopHome.stylix.cursor.size == 24;
        assert desktopHome.wayland.windowManager.hyprland.displayScaling.displays.SUNSHINE.scale == 1.5;
        assert
          desktopHome.wayland.windowManager.hyprland.displayScaling.displays.SUNSHINE.resolution == {
            width = 2562;
            height = 1656;
          };
        assert
          (builtins.head desktopHome.wayland.windowManager.hyprland.settings.monitor).output == "SUNSHINE";
        assert
          (builtins.head desktopHome.wayland.windowManager.hyprland.settings.monitor).mode == "2562x1656@120";
        assert (builtins.head desktopHome.wayland.windowManager.hyprland.settings.monitor).scale == 1.5;
        assert hasHomePackage "libreoffice";
        assert hasHomePackage "mpv-with-scripts";
        assert hasHomePackage "spotify";
        assert hasHomePackage "fuzzel";
        # The MiniDV tools embed their exact runtime dependencies in their
        # Nix-store wrappers, so those implementation packages deliberately do
        # not need to be exposed in the global system profile.
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
        assert desktop.networking.firewall.backend == "nftables";
        assert !(lib.elem 22 desktop.networking.firewall.allowedTCPPorts);
        assert lib.hasInfix "ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } tcp dport 22 accept"
          desktop.networking.firewall.extraInputRules;
        assert lib.hasInfix "ip6 saddr fc00::/7 tcp dport 22 accept"
          desktop.networking.firewall.extraInputRules;
        assert !desktop.services.openssh.openFirewall;
        assert desktop.networking.dnsBlocker.enable;
        assert desktop.services.blocky.enable;
        assert
          desktop.services.blocky.settings.ports.dns == [
            "127.0.0.1:5335"
            "[::1]:5335"
          ];
        assert desktop.services.blocky.settings.blocking.blockType == "nxDomain";
        assert desktop.services.blocky.settings.blocking.blockTTL == "15m";
        assert desktop.services.blocky.settings.blocking.clientGroupsBlock.default == [ "stevenblack" ];
        assert desktop.services.blocky.settings.rebindingProtection.enable;
        assert desktop.services.blocky.settings.dnssec.validate;
        assert desktop.services.blocky.settings.queryLog.type == "none";
        assert desktop.systemd.services.blocky.serviceConfig.AmbientCapabilities == "";
        assert desktop.systemd.services.blocky.serviceConfig.CapabilityBoundingSet == "";
        assert
          desktop.services.resolved.settings.Resolve.DNS == [
            "127.0.0.1:5335"
            "[::1]:5335"
          ];
        assert desktop.services.resolved.settings.Resolve.Domains == [ "~." ];
        assert desktop.services.resolved.settings.Resolve.FallbackDNS == [ ];
        assert desktop.services.resolved.settings.Resolve.DNSSEC == false;
        assert desktop.networking.resolvedBaseline.enable;
        assert !desktop.networking.unboundResolver.enable;
        assert !desktop.services.unbound.enable;
        assert desktop.services.resolved.settings.Resolve.DNSStubListener == true;
        assert desktop.services.resolved.settings.Resolve.LLMNR == false;
        assert desktop.services.resolved.settings.Resolve.MulticastDNS == false;
        assert desktop.services.resolved.settings.Resolve.ReadEtcHosts == true;
        assert desktop.services.resolved.settings.Resolve.ResolveUnicastSingleLabel == false;
        assert desktop.services.resolved.settings.Resolve.CacheFromLocalhost == false;
        assert desktop.services.resolved.settings.Resolve.DNSOverTLS == false;
        assert desktop.programs.chromiumPolicies.policies.DnsOverHttpsMode == "off";
        assert desktop.programs.chromiumPolicies.dnsOverHttpsMode == "off";
        assert
          desktopHome.programs.browserPolicy.chromium.extensionUpdateUrl
          == desktop.programs.chromiumPolicies.extensionUpdateUrl;
        assert
          desktopHome.programs.browserPolicy.chromium.heliumExtensions
          == desktop.programs.chromiumPolicies.heliumExtensions;
        assert desktopHome.programs.browserPolicy.blocking.customFilterLists == sharedUblockFilters;
        assert desktop.programs.chromiumPolicies.targets.google-chrome.enable;
        assert !desktop.programs.chromiumPolicies.targets.google-chrome.inheritSharedPolicies;
        assert desktop.programs.chromiumPolicies.targets.google-chrome.policies.DnsOverHttpsMode == "off";
        assert
          desktop.environment.etc."opt/chrome/policies/managed/nixos-system.json".text
          == builtins.toJSON { DnsOverHttpsMode = "off"; };
        assert desktopHome.programs.zen-browser.policies.DNSOverHTTPS.Enabled == false;
        assert desktopHome.programs.zen-browser.policies.DNSOverHTTPS.Locked;
        assert desktop.networking.performanceTuning.enable;
        assert desktop.networking.performanceTuning.congestionControl == "cubic";
        assert desktop.networking.performanceTuning.enableMtuBlackholeRecovery;
        assert desktop.networking.performanceTuning.enableSynCookies;
        assert desktop.networking.wirelessIwd.enable;
        assert desktop.networking.wireless.iwd.enable;
        assert !desktop.networking.wireless.enable;
        assert desktop.networking.useNetworkd;
        assert !desktop.networking.networkmanager.enable;
        assert desktop.networking.wireless.iwd.settings.General.EnableNetworkConfiguration == false;
        assert desktop.networking.wireless.iwd.settings.General.AddressRandomization == "disabled";
        assert desktop.networking.wireless.iwd.settings.General.AddressRandomizationRange == "full";
        assert desktop.networking.wireless.iwd.settings.General.ManagementFrameProtection == 1;
        assert desktop.networking.wireless.iwd.settings.General.DisableANQP;
        assert desktop.networking.wireless.iwd.settings.General.DisablePMKSA == false;
        assert desktop.networking.wireless.iwd.settings.Settings.AutoConnect;
        assert desktop.networking.wireless.iwd.settings.Scan.DisablePeriodicScan == false;
        assert desktop.networking.wireless.iwd.settings.General.Country == "US";
        assert desktop.networking.wireless.iwd.settings.DriverQuirks.PowerSaveDisable == "mt7921e";
        assert !(desktop.networking.wireless.iwd.settings ? IPv6);
        assert !(desktop.networking.wireless.iwd.settings ? Network);
        assert desktop.networking.wireguardBaseline.enable;
        assert desktop.networking.wireguardBaseline.backend == "networkd";
        assert desktop.networking.wireguard.useNetworkd;
        assert desktop.networking.wireguard.interfaces == { };
        assert desktop.networking.wireguardBaseline.openFirewallPorts == [ ];
        assert !desktop.networking.wireguardBaseline.allowDefaultRoutes;
        assert !lib.elem "tcp_bbr" desktop.boot.kernelModules;
        assert !(desktop.boot.kernel.sysctl ? "net.core.default_qdisc");
        assert !(desktop.boot.kernel.sysctl ? "net.ipv4.tcp_congestion_control");
        assert desktop.boot.kernel.sysctl."net.ipv4.tcp_mtu_probing" == 1;
        assert desktop.boot.kernel.sysctl."net.ipv4.tcp_syncookies" == 1;
        assert desktop.networking.fail2ban.enable;
        assert desktop.services.fail2ban.enable;
        assert desktop.services.fail2ban.banaction == "nftables-multiport";
        assert desktop.services.fail2ban.bantime == "1h";
        assert desktop.services.fail2ban.maxretry == 5;
        assert desktop.services.fail2ban.bantime-increment.enable;
        assert desktop.services.fail2ban.bantime-increment.maxtime == "7d";
        assert desktop.services.fail2ban.bantime-increment.overalljails;
        assert desktop.services.fail2ban.ignoreIP == [ ];
        assert desktop.services.fail2ban.jails.sshd.enabled;
        assert desktop.services.fail2ban.jails.DEFAULT.settings.backend == "systemd";
        assert desktop.services.fail2ban.jails.DEFAULT.settings.findtime == "15m";
        assert desktop.services.fail2ban.jails.DEFAULT.settings.usedns == "no";
        assert desktop.services.openssh.settings.LogLevel == "VERBOSE";
        assert desktop.services.openssh.ports == [ 22 ];
        assert !desktop.services.openssh.openFirewall;
        assert !desktop.services.openssh.startWhenNeeded;
        assert desktop.services.openssh.settings.PermitRootLogin == "prohibit-password";
        assert !desktop.services.openssh.settings.PasswordAuthentication;
        assert !desktop.services.openssh.settings.KbdInteractiveAuthentication;
        assert !desktop.services.openssh.settings.PermitEmptyPasswords;
        assert desktop.services.openssh.settings.PubkeyAuthentication;
        assert desktop.services.openssh.settings.AuthenticationMethods == "publickey";
        assert desktop.services.openssh.settings.UsePAM;
        assert !desktop.services.openssh.settings.AllowAgentForwarding;
        assert !desktop.services.openssh.settings.Compression;
        assert !desktop.services.openssh.settings.TCPKeepAlive;
        assert desktop.services.openssh.settings.ClientAliveInterval == 300;
        assert desktop.services.openssh.settings.ClientAliveCountMax == 3;
        assert desktop.services.openssh.settings.LoginGraceTime == 30;
        assert desktop.services.openssh.settings.MaxAuthTries == 4;
        assert desktop.services.openssh.settings.MaxStartups == "10:30:60";
        assert desktop.services.openssh.settings.PerSourceMaxStartups == 3;
        assert desktop.services.openssh.settings.PermitTunnel == "no";
        assert !desktop.services.openssh.settings.PermitUserEnvironment;
        assert desktop.services.openssh.settings.GatewayPorts == "no";
        assert !desktop.networking.tarpit.enable;
        assert !desktop.services.endlessh-go.enable;
        assert desktop.xdg.portal.enable;
        assert desktop.xdg.portal.xdgOpenUsePortal;
        assert desktop.xdg.portal.config.hyprland.default == "hyprland;gtk";
        assert desktopHome.xdg.portalHomeIntegration.enable;
        assert !desktopHome.xdg.portal.enable;
        assert !desktop.services.avahi.enable;
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
        assert desktop.console.earlySetup;
        assert desktop.console.useXkbConfig;
        assert desktop.services.getty.autologinUser == null;
        assert lib.all (module: lib.elem module desktop.boot.initrd.kernelModules) [
          "nvme"
          "btrfs"
        ];
        assert desktop.services.telegraf.enable;
        assert desktop.services.telegraf.extraConfig.outputs.prometheus_client.listen == "127.0.0.1:9273";
        assert desktop.security.wrappers.smartctl-telegraf.owner == "telegraf";
        assert desktop.services.openssh.settings.X11Forwarding == false;
        assert desktop.services.openssh.settings.UseDns == false;
        assert desktop.services.openssh.settings.StreamLocalBindUnlink == true;
        assert builtins.hasAttr "updateDiff" desktop.system.preSwitchChecks;
        assert lib.hasInfix "PATH=\"$incoming/sw/bin:$PATH\"" desktop.system.preSwitchChecks.updateDiff;
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
        assert desktop.programs.hyprland.xwayland.enable;
        assert desktop.programs.hyprland.systemd.setPath.enable;
        assert !desktopHome.wayland.windowManager.hyprland.systemd.enable;
        assert desktop.services.dbus.enable;
        assert desktop.xdg.portal.enable;
        assert desktop.xdg.portal.config.hyprland.default == "hyprland;gtk";
        assert desktop.services.pipewire.enable;
        assert desktop.services.pipewire.wireplumber.enable;
        assert lib.hasInfix "export AQ_DRM_DEVICES=/dev/dri/card1"
          desktopHome.xdg.configFile."uwsm/env-hyprland".text;
        assert !lib.hasInfix "HYPRLAND_NO_SD_VARS" desktopHome.xdg.configFile."uwsm/env-hyprland".text;
        assert !lib.hasInfix "HYPRLAND_NO_SD_NOTIFY" desktopHome.xdg.configFile."uwsm/env-hyprland".text;
        assert desktop.services.greetd.enable;
        assert !desktop.services.displayManager.gdm.enable;
        assert desktop.services.greetd.settings.initial_session.user == "ianmh";
        assert desktop.programs.hyprlock.enable;
        assert desktop.security.pam.services.hyprlock.enableGnomeKeyring;
        assert desktop.security.pam.services.passwd.enableGnomeKeyring;
        assert hasSystemPackage "seahorse";
        assert desktop.systemd.user.services.sunshine-session-lock.unitConfig.ConditionUser == "ianmh";
        assert lib.elem "sunshine-headless-output.service"
          desktop.systemd.user.services.sunshine-session-lock.unitConfig.After;
        assert lib.hasInfix "Unlock desktop" desktopHome.xdg.configFile."hypr/hyprlock.conf".text;
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
        assert lib.hasInfix "width -int 2562" macbookHome.home.activation.configureMoonlightStreaming.data;
        assert lib.hasInfix "height -int 1656" macbookHome.home.activation.configureMoonlightStreaming.data;
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
        assert desktopHome.programs.ssh.enable;
        assert desktopHome.programs.ssh.settings."*".data.AddKeysToAgent == "yes";
        assert desktopHome.programs.ssh.settings."*".data.ForwardAgent == "no";
        assert desktopHome.programs.ssh.settings."*".data.ForwardX11 == "no";
        assert desktopHome.programs.ssh.settings."*".data.HashKnownHosts == "yes";
        assert desktopHome.programs.ssh.settings."*".data.StrictHostKeyChecking == "accept-new";
        assert desktopHome.programs.ssh.settings."*".data.UpdateHostKeys == "yes";
        assert desktopHome.programs.ssh.settings."*".data.ControlPath == "/home/ianmh/.ssh/cm/%C";
        assert macbookHome.programs.ssh.enable;
        assert macbookHome.programs.ssh.settings."*".data.AddKeysToAgent == "yes";
        assert macbookHome.programs.ssh.settings."*".data.UseKeychain == "yes";
        assert macbookHome.programs.ssh.settings."*".data.ControlPath == "/Users/ianmh/.ssh/cm/%C";
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
        assert desktop.systemd.services.nix-seal-runtime.unitConfig.RequiresMountsFor == "/run/nix-seal";
        assert lib.hasInfix "/run/nix-seal/users/ianmh" desktopHome.home.activation.nixSeal.data;
        assert !lib.hasInfix "XDG_RUNTIME_DIR is required" desktopHome.home.activation.nixSeal.data;
        assert heliumUblockSettings.userSettings.importedLists == sharedUblockFilters;
        assert zenImportedLists == sharedUblockFilters;
        pkgs.runCommand "desktop-configuration-contract" { } "touch $out";

      desktop-disko-layout-contract =
        assert desktopDisko.config.hardware.storage.encryptedRoot.enable;
        assert
          desktopDisko.config.boot.initrd.luks.devices.cryptroot.device
          == "/dev/disk/by-partlabel/NIXOS-CRYPTROOT";
        assert desktopDisko.config.boot.initrd.luks.devices.cryptroot.allowDiscards;
        assert desktopDisko.config.fileSystems."/".device == "/dev/mapper/cryptroot";
        assert desktopDisko.config.fileSystems."/boot".device == "/dev/disk/by-partlabel/NIXOS-ESP";
        assert lib.elem "subvol=@root" desktopDisko.config.fileSystems."/".options;
        assert lib.elem "nodiscard" desktopDisko.config.fileSystems."/nix".options;
        assert lib.elem "subvol=@log" desktopDisko.config.fileSystems."/var/log".options;
        assert (builtins.head desktopDisko.config.swapDevices).device == "/swap/swapfile";
        assert (builtins.head desktopDisko.config.swapDevices).priority == -1;
        assert !(lib.any (swap: swap.device == "/dev/disk/by-label/swap") desktopDisko.config.swapDevices);
        pkgs.runCommand "desktop-disko-layout-contract" { } "touch $out";
    };
  };
}
