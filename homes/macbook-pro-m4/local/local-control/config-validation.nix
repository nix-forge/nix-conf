{ lib, ... }: {
  lib.localControl.mkLocalControlConfigChecker =
    { pkgs }:
    pkgs.writeShellApplication {
      name = "check-local-control-config";
      runtimeInputs = [
        pkgs.openssl
        pkgs.coreutils
      ];
      text = ''
        scratch=$(mktemp -d)
        trap 'rm -rf "$scratch"' EXIT
        export HOME="$scratch/home" XDG_CONFIG_HOME="$scratch/config" XDG_DATA_HOME="$scratch/data"
        mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
        export LOCAL_CONTROL_BROWSER_CREDENTIAL=validation-only SERVICE_PROXY_ATTESTATION=validation-only
        export LOCAL_CONTROL_PROXY_CERT="$scratch/server.pem" LOCAL_CONTROL_PROXY_KEY="$scratch/server.key"
        export LOCAL_CONTROL_PROXY_CA="$scratch/server.pem"
        # Disposable public fixtures let Caddy load TLS modules without reading
        # runtime credentials or starting listeners. Nothing is installed.
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -noenc \
          -subj /CN=configuration.example.invalid -days 1 \
          -keyout "$LOCAL_CONTROL_PROXY_KEY" -out "$LOCAL_CONTROL_PROXY_CERT" 2>/dev/null
        ${lib.getExe pkgs.caddy} adapt --validate --adapter caddyfile --config "$1"
      '';
    };
}
