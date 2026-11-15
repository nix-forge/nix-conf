{ config, lib, ... }:
let
  lanHttps = config.homelab.operations.lanHttps;
  network = builtins.fromJSON (builtins.readFile ../../../../shared/local/network.json);
in
{
  networking.dnsBlocker = {
    bootstrapUpstreams = [
      "https://1.1.1.1/dns-query"
      "https://9.9.9.9/dns-query"
    ];
    enable = true;

    # These independently operated DoH resolvers are a desktop-local privacy,
    # availability, and jurisdiction choice. Blocky uses one per query and
    # fails over when necessary rather than racing every query to both.
    upstreams = [
      "https://dns.quad9.net/dns-query"
      "https://cloudflare-dns.com/dns-query"
    ];

    # Add a domain here only after confirming it is a false positive. The
    # short block TTL makes a correction take effect promptly.
    allowlist = [ ];
    # Permit private answers for the desktop and independently hosted Pi sites.
    # No other public name may rebind to the LAN.
    rebindingAllowlist = lib.optionals lanHttps.enable (
      lib.mapAttrsToList (name: _: "${name}.${lanHttps.domain}") lanHttps.sites
      ++ map (name: "${name}.${lanHttps.domain}") network.raspberryPiHttpsSites
    );
  };

  # ACME publishes a new TXT record after its first lookup. Keep missing-name
  # answers short-lived so Blocky can see that record during propagation.
  services.blocky.settings.caching.cacheTimeNegative = lib.mkForce "30s";

  # Retire only the owned scoped DNS repair when the declarative unit takes over.
  system.activationScripts.desktopDnssecPreviewCleanup.text = ''
    source ${./scripts/retire-dnssec-preview.sh} \
      /etc/systemd/system.control/blocky.service.d/90-desktop-dnssec-preview.conf \
      /nix/var/nix/gcroots/desktop-dnssec-preview
  '';

  # Enforce the encrypted resolver path for all host processes. Namespace DNS
  # is carried inside WireGuard and has its own firewall; loopback remains
  # available for resolved and Blocky.
  networking.nftables.tables.desktop-dns-privacy = lib.mkIf config.networking.dnsBlocker.enable {
    family = "inet";
    content = ''
      chain block-plaintext-dns {
        type filter hook output priority filter; policy accept;
        oifname != "lo" tcp dport 53 drop
        oifname != "lo" udp dport 53 drop
      }
    '';
  };

  assertions = [
    {
      assertion = !config.networking.dnsBlocker.enable || config.networking.nftables.enable;
      message = "Desktop DNS privacy requires nftables to block plaintext host egress.";
    }
  ];
}
