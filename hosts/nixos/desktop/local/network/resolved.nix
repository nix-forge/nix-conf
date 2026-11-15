{
  networking.resolvedBaseline.enable = true;

  services.resolved.settings.Resolve = {
    # Blocky is the one DNSSEC validation and encrypted-upstream owner. Keep
    # resolved as the loopback stub so applications retain NSS and resolvectl
    # integration without a second validation/cache layer.
    DNSSEC = false;
    DNSOverTLS = false;
  };
}
