# Media Server Secret Bootstrap

This repo is safe to keep public as long as you only commit encrypted `*.age`
files and never commit plaintext values.

For the full per-secret reference, see `docs/media-server-secrets-reference.md`.

## Current bootstrap state

- `configs/nixos/media-server/default.nix`
- `configs/nixos/media-server-vm-parity/default.nix`
- `configs/nixos/media-server-vm-smoke/default.nix`

- `configs/nixos/media-server/default.nix` still uses your local MacBook home
  SSH public key as a temporary bootstrap recipient.
- `configs/nixos/media-server-vm-parity/default.nix` now uses the VM's fetched
  SSH host key as the primary agenix recipient.
- `configs/nixos/media-server-vm-smoke/default.nix` now uses the VM's fetched
  SSH host key as the primary agenix recipient.
- Both VM configs also include your MacBook home SSH public key as an extra
  agenix recipient so you can keep editing secrets locally.

Before deploying a real host, replace each host `secrets.publicKey` with that
machine's own SSH public key and run:

```bash
just secret-reencrypt --all
```

## VM-first workflow

1. Boot and test the VM first:

```bash
just media-vm-test parity
```

2. Start or keep the VM running and read its host SSH public key:

```bash
ssh -p 2222 root@127.0.0.1 'cat /etc/ssh/ssh_host_ed25519_key.pub'
```

3. The current VM configs are already updated with the keys extracted from the
   local qcow images. If the VM disk is regenerated from scratch later, fetch
   the new key and update the config again.

4. Re-encrypt VM secrets:

```bash
just secret-reencrypt IanHollow.system.nixos.media-server-vm-parity.cloudflare-ddns-token
just secret-reencrypt IanHollow.system.nixos.media-server-vm-parity.vaultwarden-env
just secret-reencrypt IanHollow.system.nixos.media-server-vm-parity.vpn-gluetun-env
just secret-reencrypt IanHollow.system.nixos.media-server-vm-parity.qbittorrent-env
just secret-reencrypt IanHollow.system.nixos.media-server-vm-parity.pihole-env
just secret-reencrypt IanHollow.system.nixos.media-server-vm-parity.homebridge-env
just secret-reencrypt IanHollow.system.nixos.media-server-vm-parity.scrypted-env
```

5. Repeat the same process for `configs/nixos/media-server-vm-smoke/default.nix`
   if the smoke VM qcow is recreated and its host key changes.

6. After the real server exists, fetch its host SSH public key and replace
   `configs/nixos/media-server/default.nix`, then run `just secret-reencrypt --all`.

## Secrets you need to provide

Required now:

- `cloudflare-ddns-token`
  - Cloudflare API token with Zone DNS edit access for your zone.
- `vaultwarden-env`
  - At minimum: `ADMIN_TOKEN`
  - Usually also: `DOMAIN`
- `vpn-gluetun-env`
  - Mullvad WireGuard values.
- `qbittorrent-env`
  - qBittorrent container env settings.
- `pihole-env`
  - Pi-hole admin password and timezone.
- `homebridge-env`
  - Homebridge timezone and any plugin-specific env values you need.
- `scrypted-env`
  - Scrypted auth/update token and timezone.

Optional later:

- `cloudflared-credentials`
- `cloudflared-cert`

Only create those if you enable `my.media.services.cloudflared.enable`.

## Recommended secret contents

### Cloudflare DDNS

```env
REPLACE_WITH_CLOUDFLARE_DDNS_API_TOKEN
```

### Vaultwarden

```env
ADMIN_TOKEN=REPLACE_WITH_LONG_RANDOM_ADMIN_TOKEN
DOMAIN=https://vault.example.com
SIGNUPS_ALLOWED=false
```

### Mullvad / Gluetun

Download a Mullvad WireGuard config and map it like this:

- `PrivateKey` -> `WIREGUARD_PRIVATE_KEY`
- `Address` -> `WIREGUARD_ADDRESSES`

```env
VPN_SERVICE_PROVIDER=mullvad
VPN_TYPE=wireguard
WIREGUARD_PRIVATE_KEY=REPLACE_WITH_MULLVAD_PRIVATE_KEY
WIREGUARD_ADDRESSES=REPLACE_WITH_MULLVAD_ADDRESS_CIDR
SERVER_COUNTRIES=United States
TZ=America/New_York
DOT=off
```

### qBittorrent

```env
PUID=0
PGID=0
TZ=America/New_York
WEBUI_PORT=8080
UMASK=002
```

### Pi-hole

```env
TZ=America/New_York
PIHOLE_UID=0
PIHOLE_GID=0
WEBPASSWORD=REPLACE_WITH_PIHOLE_ADMIN_PASSWORD
```

### Homebridge

```env
TZ=America/New_York
HOMEBRIDGE_CONFIG_UI=1
HOMEBRIDGE_CONFIG_UI_PORT=8581
```

### Scrypted

```env
TZ=America/New_York
SCRYPTED_WEBHOOK_UPDATE_AUTHORIZATION=REPLACE_WITH_RANDOM_TOKEN
```

## Edit commands

### Production host

```bash
just secret-edit IanHollow.system.nixos.media-server.cloudflare-ddns-token
just secret-edit IanHollow.system.nixos.media-server.vaultwarden-env
just secret-edit IanHollow.system.nixos.media-server.vpn-gluetun-env
just secret-edit IanHollow.system.nixos.media-server.qbittorrent-env
just secret-edit IanHollow.system.nixos.media-server.pihole-env
just secret-edit IanHollow.system.nixos.media-server.homebridge-env
just secret-edit IanHollow.system.nixos.media-server.scrypted-env
```

### VM parity host

```bash
just secret-edit IanHollow.system.nixos.media-server-vm-parity.cloudflare-ddns-token
just secret-edit IanHollow.system.nixos.media-server-vm-parity.vaultwarden-env
just secret-edit IanHollow.system.nixos.media-server-vm-parity.vpn-gluetun-env
just secret-edit IanHollow.system.nixos.media-server-vm-parity.qbittorrent-env
just secret-edit IanHollow.system.nixos.media-server-vm-parity.pihole-env
just secret-edit IanHollow.system.nixos.media-server-vm-parity.homebridge-env
just secret-edit IanHollow.system.nixos.media-server-vm-parity.scrypted-env
```

### VM smoke host

```bash
just secret-edit IanHollow.system.nixos.media-server-vm-smoke.cloudflare-ddns-token
just secret-edit IanHollow.system.nixos.media-server-vm-smoke.vaultwarden-env
just secret-edit IanHollow.system.nixos.media-server-vm-smoke.vpn-gluetun-env
just secret-edit IanHollow.system.nixos.media-server-vm-smoke.qbittorrent-env
just secret-edit IanHollow.system.nixos.media-server-vm-smoke.pihole-env
just secret-edit IanHollow.system.nixos.media-server-vm-smoke.homebridge-env
just secret-edit IanHollow.system.nixos.media-server-vm-smoke.scrypted-env
```

## Safety checks

Run before committing:

```bash
just secret-lint
just secret-check
```

If you want to confirm no plaintext is staged:

```bash
git diff --cached -- secrets
```
