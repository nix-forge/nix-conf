{
  # Deliberately inactive: this Wi-Fi desktop uses Blocky as its one local
  # blocking, caching, DNSSEC, and encrypted-DoH policy point. A recursive
  # Unbound instance would expose DNS metadata to authoritative servers; an
  # Unbound DoT forwarder would duplicate the existing Blocky resolver layer.
  #
  # For a deliberate migration, disable networking.dnsBlocker first, enable
  # this option, and either accept recursive DNS or configure authenticated
  # DNS-over-TLS forwarders here.
  networking.unboundResolver.enable = false;
}
