{ pkgs, desktopConfig }:
let
  blacklisted = pkgs.cacert.override { blacklist = [ "emSign ECC Root CA - G3" ]; };
  bundle = desktopConfig.security.pki.caBundle;
  aliases = [
    "ssl/certs/ca-certificates.crt"
    "ssl/certs/ca-bundle.crt"
    "pki/tls/certs/ca-bundle.crt"
  ];
in
assert !desktopConfig.security.pki.useCompatibleBundle;
assert builtins.elem "emSign ECC Root CA - G3" desktopConfig.security.pki.caCertificateBlacklist;
assert builtins.all (
  name: toString desktopConfig.environment.etc.${name}.source == toString bundle
) aliases;
pkgs.runCommand "desktop-ca-bundle-check" {
  nativeBuildInputs = [
    pkgs.gawk
    pkgs.openssl
  ];
  BASE_BUNDLE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  BASE_UNBUNDLED = "${pkgs.cacert.unbundled}/etc/ssl/certs";
  FILTERED_BUNDLE = bundle;
  FILTERED_UNBUNDLED = "${blacklisted.unbundled}/etc/ssl/certs";
  P11_SOURCE = desktopConfig.environment.etc."ssl/trust-source".source;
} (builtins.readFile ./ca-bundle.sh)
