{ pkgs, desktopConfig }:
let
  bundle = desktopConfig.security.pki.caBundle;
  aliases = [
    "ssl/certs/ca-certificates.crt"
    "ssl/certs/ca-bundle.crt"
    "pki/tls/certs/ca-bundle.crt"
  ];
in
assert !desktopConfig.security.pki.useCompatibleBundle;
assert desktopConfig.security.pki.caCertificateBlacklist == [ ];
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
  AFFECTED_CERTIFICATE = ./fixtures/emsign-ecc-root-ca-g3.pem;
  P11_SOURCE = desktopConfig.environment.etc."ssl/trust-source".source;
} (builtins.readFile ./ca-bundle.sh)
