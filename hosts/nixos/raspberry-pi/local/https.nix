{ config, lib, ... }:
let
  network = builtins.fromJSON (builtins.readFile ../../../shared/local/network.json);
  domain = network.homelabDomain;
  allowedClientCIDRs = network.raspberryPiAdminClientCIDRs;
in
{
  homelab.operations.lanHttps = {
    enable = true;
    inherit domain;
    certificateHost = domain;
    listenAddresses = [
      "127.0.0.1"
      network.raspberryPiServerAddress
    ];
    allowedCIDRs = [ "127.0.0.0/8" ] ++ allowedClientCIDRs;
  };

  security.acme = {
    acceptTerms = true;
    certs.${domain} = {
      dnsProvider = "cloudflare";
      extraDomainNames = [ "*.${domain}" ];
      credentialFiles.CF_DNS_API_TOKEN_FILE = config.nixSeal.secrets.cloudflare-dns-token.path;
      group = "nginx";
      reloadServices = [ "nginx.service" ];
      dnsResolver = "192.168.40.1:53";
    };
  };

  # The gateway resolver can check the TXT record without direct outbound DNS
  # access to Cloudflare's authoritative name servers.
  systemd.services."acme-order-renew-${domain}" = {
    requires = [ "nix-seal-activate.service" ];
    after = [ "nix-seal-activate.service" ];
    environment = {
      LEGO_DNS_PROPAGATION_DISABLE_ANS = "true";
      CLOUDFLARE_PROPAGATION_TIMEOUT = "600";
    };
  };

  services.nginx = {
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
  };
  systemd.services.nginx = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };

  # Keep the admin sites off other VLANs and the Pi's public IPv6 address.
  networking.firewall.extraInputRules = lib.mkAfter ''
    ${lib.concatMapStringsSep "\n" (
      cidr: ''iifname "eth0" ip saddr ${cidr} tcp dport 443 accept comment "Pi HTTPS client"''
    ) allowedClientCIDRs}
  '';
  assertions = [
    {
      assertion =
        config.networking.nftables.enable
        && !builtins.elem 443 config.networking.firewall.allowedTCPPorts
        && !builtins.elem 80 config.networking.firewall.allowedTCPPorts;
      message = "Pi HTTPS must use a source-scoped firewall rule and no HTTP listener.";
    }
    {
      assertion =
        builtins.length (lib.unique network.raspberryPiHttpsSites)
        == builtins.length network.raspberryPiHttpsSites
        &&
          builtins.length (builtins.attrNames config.homelab.operations.lanHttps.sites)
          == builtins.length network.raspberryPiHttpsSites
        && lib.all (
          name: builtins.hasAttr name config.homelab.operations.lanHttps.sites
        ) network.raspberryPiHttpsSites;
      message = "The shared Pi HTTPS site inventory must match the Pi's declared HTTPS routes.";
    }
  ];
}
