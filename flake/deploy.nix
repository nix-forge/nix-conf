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
        assert desktop.networking.firewall.backend == "nftables";
        assert !(lib.elem 22 desktop.networking.firewall.allowedTCPPorts);
        assert lib.hasInfix "ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } tcp dport 22 accept"
          desktop.networking.firewall.extraInputRules;
        assert lib.hasInfix "ip6 saddr fc00::/7 tcp dport 22 accept"
          desktop.networking.firewall.extraInputRules;
        assert !desktop.services.openssh.openFirewall;
        assert !desktop.services.avahi.enable;
        assert desktop.programs.nh.enable;
        assert desktop.services.telegraf.enable;
        assert desktop.services.telegraf.extraConfig.outputs.prometheus_client.listen == "127.0.0.1:9273";
        assert desktop.security.wrappers.smartctl-telegraf.owner == "telegraf";
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
        assert desktop.services.pipewire.alsa.support32Bit;
        assert desktop.fileSystems.${gamesMountPoint}.device == gamesDevice;
        assert desktop.fileSystems.${gamesMountPoint}.fsType == "btrfs";
        assert lib.all (option: lib.elem option desktop.fileSystems.${gamesMountPoint}.options) [
          "subvol=games"
          "compress=zstd:1"
          "noatime"
          "discard=async"
          "nofail"
          "x-systemd.device-timeout=10s"
        ];
        assert lib.elem gamesMountPoint desktop.services.btrfs.autoScrub.fileSystems;
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
