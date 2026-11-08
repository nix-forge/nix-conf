{
  config,
  lib,
  pkgs,
  ...
}:
let
  retirePreview = pkgs.writers.writePython3 "retire-desktop-trust-preview" {
    # Ruff owns wrapping; retain all other writer checks.
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ./scripts/retire-trust-preview.py);
in
{
  # Use NixOS's Mozilla-derived bundle and preserve p11-kit trust metadata.
  # This desktop has no approved private or TLS-interception CA. Each added
  # root expands who can authenticate arbitrary TLS endpoints. Explicitly
  # distrust the compromised emSign G3 root (GHSA-6q48-6c7w-9gw2) while
  # preserving unrelated public roots and the native distrust metadata.
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
    caCertificateBlacklist = [ "emSign ECC Root CA - G3" ];
  };

  # Retire the narrowly scoped boot bridge only after normal activation has
  # installed this generation's complete trust policy. Unknown files stay put.
  system.activationScripts.desktopTrustPreviewCleanup = {
    deps = [ "etc" ];
    text = lib.escapeShellArgs [
      (toString retirePreview)
      (toString config.security.pki.caBundle)
      (toString config.environment.etc."ssl/trust-source".source)
    ];
  };
}
