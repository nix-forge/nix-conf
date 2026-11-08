{
  config,
  lib,
  pkgs,
  ...
}:
let
  network = builtins.fromJSON (builtins.readFile ../../../shared/local/network.json);
  managementClientCIDRs = network.raspberryPiAdminClientCIDRs;
  managementKeys = [
    (builtins.readFile ./keys/desktop.pub)
    (builtins.readFile ./keys/macbook.pub)
  ];
in
{
  system.stateVersion = "26.05";
  time.timeZone = "America/Los_Angeles";
  boot.loader.raspberry-pi.bootloader = "uboot";
  boot.loader.generic-extlinux-compatible.configurationLimit = 5;
  boot.initrd.availableKernelModules = [
    "mmc_block"
    "sdhci_iproc"
    "genet"
  ];
  boot.swraid.enable = false;
  hardware.bluetooth.enable = false;
  networking = {
    nftables.enable = true;
    usePredictableInterfaceNames = false;
    useDHCP = false;
    useNetworkd = true;
    wireless.enable = false;
    firewall = {
      enable = true;
      # Match the management and mDNS destinations explicitly. IPv6 router
      # advertisements must not make SSH reachable from the public internet.
      extraInputRules = lib.mkAfter ''
        ${lib.concatMapStringsSep "\n" (
          cidr: ''iifname "eth0" ip saddr ${cidr} tcp dport 22 accept comment "Pi SSH management"''
        ) managementClientCIDRs}
        iifname "eth0" ip daddr 224.0.0.251 udp dport 5353 accept comment "Pi IPv4 mDNS"
        iifname "eth0" ip6 daddr ff02::fb udp dport 5353 accept comment "Pi IPv6 mDNS"
      '';
    };
  };
  systemd.network.networks."10-ethernet" = {
    matchConfig.Name = "eth0";
    networkConfig = {
      DHCP = "yes";
      IPv6AcceptRA = true;
      # Avahi owns mDNS advertisement and plugin discovery on this interface.
      MulticastDNS = false;
    };
    linkConfig.RequiredForOnline = "routable";
  };
  systemd.services.systemd-networkd.stopIfChanged = false;
  systemd.services.systemd-resolved.stopIfChanged = false;
  services.resolved.enable = true;
  services.avahi = {
    enable = true;
    openFirewall = false;
    nssmdns4 = true;
    settings = {
      server = {
        allow-interfaces = [ "eth0" ];
        # HomeKit accepts only Trusted IPv4 clients at the host firewall.
        # Advertise addresses that those clients can reach.
        use-ipv6 = false;
      };
      publish = {
        disable-publishing = false;
        disable-user-service-publishing = false;
        publish-addresses = true;
        publish-aaaa-on-ipv4 = false;
      };
    };
  };
  users.mutableUsers = false;
  users.users = {
    ianmh = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = managementKeys;
      hashedPassword = "!";
    };
    root.openssh.authorizedKeys.keys = managementKeys;
  };
  security.sudo.wheelNeedsPassword = false;
  services.openssh.settings = {
    PermitRootLogin = "prohibit-password";
    AllowUsers = [
      "ianmh"
      "root"
    ];
  };
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      max-jobs = 1;
      cores = 2;
      auto-optimise-store = true;
      trusted-users = [ "root" ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
      persistent = true;
    };
  };
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };
  services.journald.settings.Journal = {
    SystemMaxUse = "128M";
    RuntimeMaxUse = "32M";
    MaxRetentionSec = "14day";
  };
  systemd.coredump.enable = false;
  environment.systemPackages = with pkgs; [
    htop
    curl
  ];
  assertions = [
    {
      assertion =
        !builtins.elem 22 config.networking.firewall.allowedTCPPorts
        && !builtins.elem 22 (
          lib.attrByPath [ "eth0" "allowedTCPPorts" ] [ ] config.networking.firewall.interfaces
        )
        && !config.services.openssh.openFirewall;
      message = "Pi SSH must remain source scoped by the host firewall.";
    }
    {
      assertion = config.boot.loader.raspberry-pi.variant == "4";
      message = "This host targets the verified Raspberry Pi 4.";
    }
    {
      assertion = !config.services.avahi.reflector;
      message = "Cross-VLAN mDNS belongs to the gateway, not the Pi.";
    }
  ];
}
