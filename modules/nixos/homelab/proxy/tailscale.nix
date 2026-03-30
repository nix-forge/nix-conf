{
  lib,
  config,
  pkgs,
  ...
}:
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
  };

  systemd.services.tailscaled-autoconnect.serviceConfig.TimeoutStartSec = "20s";

  systemd.tmpfiles.rules = [ "d /var/lib/tailscale-cert 0750 root nginx - -" ];

  systemd.services.tailscale-cert = {
    description = "Fetch Tailscale TLS certificate for nginx";
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
    requiredBy = lib.optional config.services.nginx.enable "nginx.service";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
    };
    path = with pkgs; [
      coreutils
      jq
      tailscale
    ];
    script = ''
      set -euo pipefail

      cert_dir=/var/lib/tailscale-cert
      dns_name="$(tailscale status --json | jq -r '.Self.DNSName // "" | rtrimstr(".")')"

      if [ -z "$dns_name" ]; then
        echo "tailscale DNS name is not available yet" >&2
        exit 1
      fi

      umask 027
      mkdir -p "$cert_dir"

      tmp_cert=$(mktemp)
      tmp_key=$(mktemp)
      trap 'rm -f "$tmp_cert" "$tmp_key"' EXIT

      tailscale cert --cert-file "$tmp_cert" --key-file "$tmp_key" "$dns_name"

      changed=0

      if ! test -f "$cert_dir/cert.pem" || ! cmp -s "$tmp_cert" "$cert_dir/cert.pem"; then
        install -m 0640 -o nginx -g nginx "$tmp_cert" "$cert_dir/cert.pem"
        changed=1
      fi

      if ! test -f "$cert_dir/key.pem" || ! cmp -s "$tmp_key" "$cert_dir/key.pem"; then
        install -m 0640 -o nginx -g nginx "$tmp_key" "$cert_dir/key.pem"
        changed=1
      fi

      printf '%s\n' "$dns_name" > "$cert_dir/dns-name"

      if [ "$changed" -eq 1 ] && systemctl is-active --quiet nginx.service; then
        systemctl reload nginx.service
      fi
    '';
  };

  systemd.timers.tailscale-cert = {
    wantedBy = [ "timers.target" ];
    partOf = [ "tailscale-cert.service" ];
    timerConfig = {
      OnBootSec = "10m";
      OnCalendar = "daily";
      RandomizedDelaySec = "6h";
      Persistent = true;
    };
  };

  systemd.services.nginx = lib.mkIf config.homelab.proxy.tailscaleTls.enable {
    after = [ "tailscale-cert.service" ];
    requires = [ "tailscale-cert.service" ];
    wants = [ "tailscale-cert.service" ];
  };
}
