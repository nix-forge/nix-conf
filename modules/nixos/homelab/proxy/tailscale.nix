{
  lib,
  config,
  pkgs,
  ...
}:
let
  certDir = "/var/lib/tailscale-cert";

  certFetchScript = ''
    set -euo pipefail

    cert_dir="${certDir}"
    dns_name=""

    for _ in $(seq 1 60); do
      dns_name="$(tailscale status --json | jq -r '.Self.DNSName // "" | rtrimstr(".")')"
      if [ -n "$dns_name" ]; then
        break
      fi
      sleep 2
    done

    if [ -z "$dns_name" ]; then
      echo "tailscale DNS name is not available yet" >&2
      exit 1
    fi

    umask 027
    mkdir -p "$cert_dir"

    tmp_cert=$(mktemp "$cert_dir/cert.pem.tmp.XXXXXX")
    tmp_key=$(mktemp "$cert_dir/key.pem.tmp.XXXXXX")
    trap 'rm -f "$tmp_cert" "$tmp_key"' EXIT

    tailscale cert --cert-file "$tmp_cert" --key-file "$tmp_key" "$dns_name"

    changed=0

    if ! test -f "$cert_dir/cert.pem" || ! cmp -s "$tmp_cert" "$cert_dir/cert.pem"; then
      install -m 0640 "$tmp_cert" "$cert_dir/cert.pem"
      changed=1
    fi

    if ! test -f "$cert_dir/key.pem" || ! cmp -s "$tmp_key" "$cert_dir/key.pem"; then
      install -m 0640 "$tmp_key" "$cert_dir/key.pem"
      changed=1
    fi

    printf '%s\n' "$dns_name" > "$cert_dir/dns-name"
    chmod 0640 "$cert_dir/dns-name"

    if [ "$changed" -eq 1 ] && systemctl is-active --quiet nginx.service; then
      systemctl reload nginx.service
    fi
  '';
in
{
  assertions = [
    {
      assertion =
        (!config.services.tailscale.enable)
        || lib.hasAttrByPath [ "age" "secrets" "tailscale-auth-key" ] config;
      message = "age.secrets.tailscale-auth-key must exist when importing homelab.proxy.tailscale.";
    }
  ];

  services.tailscale = {
    enable = true;
    openFirewall = false;
    authKeyFile = config.age.secrets.tailscale-auth-key.path;
    permitCertUid = if config.services.nginx.enable then config.services.nginx.user else null;
  };

  systemd.services.tailscaled-autoconnect.serviceConfig.TimeoutStartSec = "20s";

  systemd.services.tailscale-cert-bootstrap = {
    description = "Fetch initial Tailscale TLS certificate for nginx";
    after = [
      "network-online.target"
      "tailscaled.service"
      "tailscaled-autoconnect.service"
    ];
    before = [ "nginx.service" ];
    wants = [
      "network-online.target"
      "tailscaled-autoconnect.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = config.services.nginx.user;
      Group = config.services.nginx.group;
      Restart = "on-failure";
      RestartSec = "20s";
      TimeoutStartSec = "15min";
      StateDirectory = "tailscale-cert";
      StateDirectoryMode = "0750";
    };
    path = with pkgs; [
      coreutils
      diffutils
      jq
      tailscale
    ];
    script = ''
      if test -s ${certDir}/cert.pem && test -s ${certDir}/key.pem && test -s ${certDir}/dns-name; then
        exit 0
      fi

      ${certFetchScript}
    '';
  };

  systemd.services.tailscale-cert-refresh = {
    description = "Refresh Tailscale TLS certificate for nginx";
    after = [
      "network-online.target"
      "tailscaled.service"
      "tailscaled-autoconnect.service"
    ];
    wants = [
      "network-online.target"
      "tailscaled-autoconnect.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      User = config.services.nginx.user;
      Group = config.services.nginx.group;
      TimeoutStartSec = "15min";
      StateDirectory = "tailscale-cert";
      StateDirectoryMode = "0750";
    };
    path = with pkgs; [
      coreutils
      diffutils
      jq
      tailscale
    ];
    script = certFetchScript;
  };

  systemd.timers.tailscale-cert-refresh = {
    wantedBy = [ "timers.target" ];
    partOf = [ "tailscale-cert-refresh.service" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "12h";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
  };

  systemd.services.nginx = lib.mkIf config.services.nginx.enable {
    after = [ "tailscale-cert-bootstrap.service" ];
    requires = [ "tailscale-cert-bootstrap.service" ];
    wants = [ "tailscale-cert-bootstrap.service" ];
  };
}
