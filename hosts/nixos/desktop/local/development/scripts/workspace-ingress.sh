# shellcheck shell=bash
rules="$(nft list chain inet nixos-fw input-allow)"
if [[ $rules == *'comment "local workspace ingress"'* ]]; then
  exit 0
fi
nft insert rule inet nixos-fw input-allow iifname '"virbr-mgmt"' ip saddr 192.168.123.12 ip daddr 192.168.123.1 tcp dport '{ 8443, 8444 }' accept comment '"local workspace ingress"'
