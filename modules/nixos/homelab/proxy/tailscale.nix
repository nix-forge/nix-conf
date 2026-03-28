{
  lib,
  config,
  pkgs,
  ...
}:
{
  assertions = [
    {
      assertion = lib.hasAttrByPath [ "age" "secrets" "tailscale-auth-key" ] config;
      message = "age.secrets.tailscale-auth-key must exist when importing homelab.proxy.tailscale.";
    }
  ];

  services.tailscale = {
    enable = true;
    openFirewall = false;
    useRoutingFeatures = "client";
    authKeyFile = config.age.secrets.tailscale-auth-key.path;
    permitCertUid = "nginx";
    extraUpFlags = [ "--accept-dns=true" ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/tailscale-cert 0750 root nginx - -"
  ];

  systemd.services.tailscale-cert = {
    description = "Fetch Tailscale TLS certificate for nginx";
    after = [
      "network-online.target"
      "tailscaled.service"
      "tailscaled-autoconnect.service"
    ];
    wants = [
      "network-online.target"
      "tailscaled-autoconnect.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
    };
    path = with pkgs; [
      coreutils
      gnugrep
      python3
      tailscale
    ];
    script = ''
      set -eu

      cert_dir=/var/lib/tailscale-cert
      dns_name="$(${pkgs.tailscale}/bin/tailscale status --json | ${pkgs.python3}/bin/python3 -c 'import json, sys; print((json.load(sys.stdin).get("Self", {}).get("DNSName") or "").rstrip("."))')"

      if [ -z "$dns_name" ]; then
        echo "tailscale DNS name is not available yet" >&2
        exit 1
      fi

      umask 027
      mkdir -p "$cert_dir"

      tmp_cert=$(mktemp)
      tmp_key=$(mktemp)
      trap 'rm -f "$tmp_cert" "$tmp_key"' EXIT

      ${pkgs.tailscale}/bin/tailscale cert --cert-file "$tmp_cert" --key-file "$tmp_key" "$dns_name"

      install -m 0640 -o nginx -g nginx "$tmp_cert" "$cert_dir/cert.pem"
      install -m 0640 -o nginx -g nginx "$tmp_key" "$cert_dir/key.pem"
      printf '%s\n' "$dns_name" > "$cert_dir/dns-name"

      if systemctl is-active --quiet nginx.service; then
        systemctl reload nginx.service
      fi
    '';
  };

  systemd.timers.tailscale-cert = {
    wantedBy = [ "timers.target" ];
    partOf = [ "tailscale-cert.service" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "12h";
      RandomizedDelaySec = "30m";
    };
  };
}
