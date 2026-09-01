{ lib, ... }: {
  # Keep only the streaming defaults declarative.  Moonlight's pairing key,
  # certificate, and host list remain mutable cryptographic/user state in the
  # same preference domain and are never replaced by this activation.
  home.activation.configureMoonlightStreaming = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    source ${./scripts/configure-moonlight.sh}
  '';
}
