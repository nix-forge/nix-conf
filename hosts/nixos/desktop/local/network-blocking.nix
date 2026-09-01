{
  networking.dnsBlocker = {
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
    rebindingAllowlist = [ ];
  };
}
