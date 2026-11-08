{
  inputs,
  pkgs,
  myLib,
}:
let
  inherit (pkgs) lib;
  inherit (import ./module-fixtures.nix { inherit inputs pkgs myLib; })
    homeFor
    systemFor
    valid
    rejects
    ;
  feishin = homeFor [ ../../modules/home/feishin.nix ];
  feishinInvalid = homeFor [
    ../../modules/home/feishin.nix
    {
      programs.feishin.managedLogin = {
        url = "https://music.example.test";
        usernameFile = "/run/credentials/username";
        passwordFile = "/nix/store/password";
      };
    }
  ];
  feishinCustomPlayer = homeFor [
    ../../modules/home/feishin.nix
    { programs.mpv.package = lib.makeOverridable (_: pkgs.writeShellScriptBin "mpv" "exit 0") { }; }
  ];
  feishinDisabledPlayer = homeFor [
    ../../modules/home/feishin.nix
    { programs.mpv.enable = lib.mkForce false; }
  ];
  noctalia = homeFor [
    ../../modules/home/desktop/noctalia.nix
    {
      desktop.noctalia.enable = true;
      wayland.windowManager.hyprland.enable = true;
    }
  ];
  themedVscode = homeFor [
    (import ../../modules/shared/stylix/targets/vscode/home.nix).homeManager
    { programs.vscode.enable = true; }
  ];
  fzf = homeFor [ ../../modules/home/shells/fzf.nix ];
  fzfWithAtuin = homeFor [
    ../../modules/home/shells/fzf.nix
    { programs.atuin.enable = true; }
  ];
  atuin =
    integration:
    homeFor [
      ../../modules/home/shells/atuin.nix
      {
        programs.nushell.enable = true;
        programs.atuin = {
          enableNushellIntegration = integration;
          package = pkgs.atuin // {
            version = "18.19.0";
          };
        };
      }
    ];
  ghostty = homeFor [
    ../../modules/home/terminals/ghostty/defaultterminal.nix
    {
      programs.ghostty.package = null;
      programs.ghostty.systemd.enable = false;
      programs.bash.enable = true;
    }
  ];
  applications = homeFor [
    ../../modules/home/desktop/applications.nix
    { desktop.applications.enable = true; }
  ];
  applicationsWithoutManager = homeFor [
    ../../modules/home/desktop/applications.nix
    {
      desktop.applications.enable = true;
      systemd.user.enable = false;
    }
  ];
  applicationsWithoutAgent = homeFor [
    ../../modules/home/desktop/applications.nix
    {
      desktop.applications.enable = true;
      systemd.user.enable = false;
      services.polkit-gnome.enable = false;
    }
  ];
  clipboard = homeFor [
    ../../modules/home/desktop/clipboard.nix
    { desktop.clipboard.enable = true; }
  ];
  ssd = systemFor [
    ../../modules/nixos/hardware/ssd.nix
    { services.fstrim.enable = false; }
  ];
  wordlist = systemFor [
    ../../modules/nixos/base/wordlist.nix
    {
      environment.wordlistBaseline.enable = true;
      environment.wordlist.lists = lib.mkForce { };
    }
  ];
  portableKernel = systemFor [ ../../modules/nixos/base/kernel/default.nix ];
  editor = homeFor [
    ../../modules/home/neovim/defaulteditor.nix
    ({ inputs, ... }: import ../../modules/home/neovim/default.nix { inherit inputs; })
  ];
  visual = homeFor [
    ../../modules/home/vscode/defaultvisual.nix
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      import ../../modules/home/vscode/default.nix { inherit config lib pkgs; }
    )
  ];
  themedSystem = systemFor [
    (import ../../modules/shared/stylix/targets/authentication/nixos.nix).nixos
  ];
  actual = homeFor [ ../../modules/home/actual.nix ];
  idle = homeFor [
    ../../modules/home/desktop/idle.nix
    {
      desktop.idle.enable = true;
      wayland.windowManager.hyprland.enable = true;
    }
  ];
  core = homeFor [
    ../../modules/home/desktop/core.nix
    {
      desktop.enable = true;
      wayland.windowManager.hyprland.enable = true;
    }
  ];
  nightLight = homeFor [
    ../../modules/home/desktop/night-light.nix
    { desktop.nightLight.enable = true; }
  ];
  hdr = homeFor [
    ../../modules/home/desktop/hdr.nix
    {
      desktop.hdr = {
        enable = true;
        output = "DP-9";
      };
      wayland.windowManager.hyprland.enable = true;
    }
  ];
  manager = systemFor [
    ../../modules/nixos/network/manager.nix
    { networking.networkManagerBaseline.enable = true; }
  ];
  managerWithUnbound = systemFor [
    ../../modules/nixos/network/manager.nix
    ../../modules/nixos/network/unbound.nix
    {
      networking.networkManagerBaseline.enable = true;
      networking.unboundResolver.enable = true;
    }
  ];
  bluetooth = systemFor [
    ../../modules/nixos/hardware/bluetooth.nix
    {
      hardware.bluetooth.enable = false;
      services.pipewire.enable = false;
    }
  ];
  tarpit =
    enabled:
    systemFor [
      ../../modules/nixos/network/tarpit.nix
      {
        networking = {
          tarpit = {
            enable = true;
            allowedSources = [ "192.0.2.0/24" ];
          };
          nftables.enable = true;
          firewall.enable = enabled;
        };
      }
    ];
  publicTarpitRange = systemFor [
    ../../modules/nixos/network/tarpit.nix
    {
      networking = {
        tarpit = {
          enable = true;
          allowedSources = [ "192.0.2.0/24" ];
        };
        nftables.enable = true;
        firewall.allowedTCPPortRanges = [
          {
            from = 2200;
            to = 2300;
          }
        ];
      };
    }
  ];
  blocker = systemFor [
    ../../modules/nixos/network/blocking.nix
    {
      networking = {
        enableIPv6 = false;
        dnsBlocker = {
          enable = true;
          port = 15335;
          upstreams = [ "https://dns.example.test/dns-query" ];
          bootstrapUpstreams = [ "https://1.1.1.1/dns-query" ];
        };
      };
    }
  ];
  unbound =
    forwarders:
    systemFor [
      ../../modules/nixos/network/unbound.nix
      {
        networking.unboundResolver = {
          enable = true;
          mode = "forward-tls";
          inherit forwarders;
        };
      }
    ];
  secureBoot = systemFor [
    ../../modules/nixos/boot/secure-boot.nix
    {
      security.secureBootLanzaboote = {
        enable = true;
        pkiBundle = "/var/lib/signing";
      };
      boot.loader.efi.canTouchEfiVariables = true;
    }
  ];
  minecraft = systemFor [
    ../../modules/nixos/server/minecraft
    { services.minecraft-server.eula = true; }
  ];
  kernel = systemFor [
    ../../modules/nixos/security/kernel.nix
    { security.kernelBaseline.enable = true; }
  ];
  report = {
    editorOwnsProvider = valid editor && editor.programs.nvf.enable;
    visualOwnsProvider = valid visual && visual.programs.vscode.enable;
    fzfKeepsHistoryWithoutAtuin = valid fzf && fzf.programs.fzf.historyWidget.command != "";
    fzfSharesHistoryWithAtuin =
      valid fzfWithAtuin && fzfWithAtuin.programs.fzf.historyWidget.command == "";
    atuinChecksSelectedPackage = rejects "18.20.1" (atuin true) && valid (atuin false);
    ghosttyAllowsExternalPackage = valid ghostty && ghostty.home.sessionVariables.TERMINAL == "ghostty";
    applicationsKeepIndependentApplet =
      valid applications && !(applications.xdg.configFile ? "autostart/blueman.desktop");
    applicationsRequireAgentManager = rejects "Polkit agent requires" applicationsWithoutManager;
    applicationsAllowAlternateAgent =
      valid applicationsWithoutAgent && !(applicationsWithoutAgent.systemd.user.services ? polkit-gnome);
    clipboardOwnsLockCleanup = valid clipboard && clipboard.systemd.user.services ? cliphist-lock;
    disabledTrimHasNoUnits = !(ssd.systemd.services ? fstrim) && !(ssd.systemd.timers ? fstrim);
    wordlistReportsMissingSource = rejects "standard WORDLIST" wordlist;
    kernelSupportsHostPlatform =
      valid portableKernel && !(portableKernel.boot.kernelPackages.kernel.meta.broken or false);
    feishinWithoutSecrets =
      valid feishin
      && !(builtins.fromJSON feishin.xdg.configFile."feishin/managed.json".text ? managed_login);
    rejectsStoreCredentials = rejects "runtime paths" feishinInvalid;
    feishinPlayerIsGenerated = builtins.isString (toString feishin.xdg.configFile."feishin/mpv".source);
    feishinCustomPlayerIsGenerated =
      valid feishinCustomPlayer
      && builtins.isString (toString feishinCustomPlayer.xdg.configFile."feishin/mpv".source);
    feishinRejectsDisabledPlayer =
      rejects "mpv.enable" feishinDisabledPlayer
      && builtins.isString (toString feishinDisabledPlayer.xdg.configFile."feishin/mpv".source);
    noctaliaWithoutSiblingModules =
      valid noctalia
      && builtins.isString (
        toString noctalia.xdg.configFile."noctalia/zz-nix-desktop-features.toml".source
      );
    standaloneThemeTarget =
      valid themedVscode
      && themedVscode.stylix.enable
      && themedVscode.programs.vscode.profiles.default.userSettings."workbench.colorTheme" != "";
    themeWithoutGreeter = valid themedSystem && themedSystem.stylix.enable;
    actualWithoutUserDirs = actual.services.actual.dataDir == "/home/tester/Documents/Actual";
    idleWithoutClipboard =
      lib.hasInfix "on_lock_cmd=true"
        idle.xdg.configFile."hypr/hypridle.conf".text;
    coreDeclaresChildren =
      core.desktop.capture.enable
      && core.desktop.clipboard.enable
      && core.desktop.idle.enable
      && core.desktop.bar.enable;
    nightLightRequiresCompositor = rejects "Hyprland" nightLight;
    hdrUsesPreferredMode =
      valid hdr
      && (builtins.head hdr.wayland.windowManager.hyprland.settings.monitor).mode == "preferred";
    managerWithoutTrustedUsers =
      valid manager
      && manager.services.resolved.enable
      && manager.networking.networkmanager.dns == "systemd-resolved";
    managerWithValidatingResolver =
      valid managerWithUnbound && managerWithUnbound.networking.networkmanager.dns == "none";
    bluetoothDisabled =
      !(bluetooth.systemd.services ? bluetooth-disable-pairing)
      && !(bluetooth.services.pipewire.wireplumber.extraConfig ? "10-bluetooth-policy");
    tarpitRequiresFirewall = rejects "nftables firewall" (tarpit false) && valid (tarpit true);
    tarpitRejectsGlobalPortRanges = rejects "source-scoped" publicTarpitRange;
    blockerWithoutIpv6 =
      valid blocker
      && blocker.services.blocky.settings.ports.dns == [ "127.0.0.1:15335" ]
      && blocker.services.resolved.settings.Resolve.DNS == [ "127.0.0.1:15335" ];
    unboundAuthenticatesForwarders =
      valid (unbound [ "9.9.9.9@853#dns.quad9.net" ])
      && rejects "authenticated" (unbound [ "9.9.9.9@853" ]);
    secureBootWithoutMacPolicy = valid secureBoot;
    kernelWithoutMacPolicy = valid kernel;
    minecraftWithoutExternalInput = valid minecraft && minecraft.services.minecraft-server.enable;
  };
in
assert lib.assertMsg (lib.all (value: value) (lib.attrValues report)) (
  "Independent module contracts failed: " + builtins.toJSON report
);
pkgs.runCommand "module-independence"
  {
    report = builtins.toJSON report;
    passAsFile = [ "report" ];
  }
  ''
    cp "$reportPath" "$out"
  ''
