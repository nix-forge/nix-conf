{
  # Use NixOS's Mozilla-derived bundle and preserve p11-kit trust metadata.
  # This desktop has no approved private CA, enterprise TLS-interception CA,
  # or business-specific distrust requirement.  Keeping these lists empty is
  # intentional: every added root expands who can authenticate arbitrary TLS
  # endpoints to system applications.
  #
  # If a future network or local service genuinely needs a private root, add
  # its public PEM certificate through `certificateFiles` here only after
  # independently verifying its fingerprint and intended scope.  Do not add
  # private keys or use `certificates` for opaque inline blobs.
  security.pki = {
    installCACerts = true;
    useCompatibleBundle = false;
    certificateFiles = [ ];
    certificates = [ ];
    caCertificateBlacklist = [ ];
  };
}
