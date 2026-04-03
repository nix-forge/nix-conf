#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE_HOST=${1:-media-server-vm-parity}
DEST_HOST=${2:-media-server-vm-smoke}

secrets=(
	cloudflare-ddns-token
	vaultwarden-env
	vpn-gluetun-env
	qbittorrent-env
	pihole-env
	homebridge-env
	scrypted-env
)

tmpdir=$(mktemp -d)
cleanup() {
	rm -rf "$tmpdir"
}
trap cleanup EXIT

for secret_name in "${secrets[@]}"; do
	secret_id="IanHollow.system.nixos.${SOURCE_HOST}.${secret_name}"
	out_file="$tmpdir/${secret_name}"
	just --justfile "$ROOT_DIR/justfile" secret-view "$secret_id" >"$out_file"
	just --justfile "$ROOT_DIR/justfile" secret-encrypt "IanHollow.system.nixos.${DEST_HOST}.${secret_name}" "$out_file"
done

just --justfile "$ROOT_DIR/justfile" secret-check
