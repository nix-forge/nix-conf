{ config, lib, ... }: {
  security.pki = {
    # NixOS derives this bundle from the Mozilla root program and also exposes
    # p11-kit trust data.  This gives command-line and system services one
    # maintained trust store, including upstream distrust information.
    installCACerts = lib.mkDefault true;

    # Do not use the PEM-only compatibility bundle: it strips OpenSSL/p11-kit
    # trust rules, including purpose restrictions and distrust metadata.
    useCompatibleBundle = lib.mkDefault false;
  };

  assertions = [
    {
      assertion = config.security.pki.installCACerts;
      message = "This security PKI baseline requires the system CA bundle; use a minimal image profile instead of disabling it here.";
    }
    {
      assertion = !config.security.pki.useCompatibleBundle;
      message = "security.pki.useCompatibleBundle removes certificate trust rules. Fix the incompatible application or scope a separate, reviewed bundle to it instead.";
    }
  ];

  # Trust anchors and exclusions are security-sensitive, system-specific
  # policy.  Declare them under a host's local/ directory after independently
  # verifying the certificate fingerprint, issuer, validity period, key usage,
  # and the exact service that needs it.  Certificate files are public CA
  # material and may enter the Nix store; never place a private key there.
}
