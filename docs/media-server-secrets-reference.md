# Media Server Secrets Reference

This document lists every secret currently required by the media-server stack,
what it is used for, where to get it, and how to store it safely with agenix in
this public repository.

## Safety rules

- Never commit plaintext `.env`, token, cert, or private key files.
- Only create or modify secrets through `just secret-edit`,
  `just secret-encrypt`, or `just secret-reencrypt`.
- Before committing, run:

```bash
just secret-lint
just secret-check
```

## Secret IDs you will edit

### Production

```bash
just secret-edit IanHollow.system.nixos.media-server.cloudflare-ddns-token
just secret-edit IanHollow.system.nixos.media-server.vaultwarden-env
just secret-edit IanHollow.system.nixos.media-server.vpn-gluetun-env
just secret-edit IanHollow.system.nixos.media-server.qbittorrent-env
just secret-edit IanHollow.system.nixos.media-server.pihole-env
just secret-edit IanHollow.system.nixos.media-server.homebridge-env
just secret-edit IanHollow.system.nixos.media-server.scrypted-env
```

### VM parity

```bash
just secret-edit IanHollow.system.nixos.media-server-vm-parity.cloudflare-ddns-token
just secret-edit IanHollow.system.nixos.media-server-vm-parity.vaultwarden-env
just secret-edit IanHollow.system.nixos.media-server-vm-parity.vpn-gluetun-env
just secret-edit IanHollow.system.nixos.media-server-vm-parity.qbittorrent-env
just secret-edit IanHollow.system.nixos.media-server-vm-parity.pihole-env
just secret-edit IanHollow.system.nixos.media-server-vm-parity.homebridge-env
just secret-edit IanHollow.system.nixos.media-server-vm-parity.scrypted-env
```

### VM smoke

```bash
just secret-edit IanHollow.system.nixos.media-server-vm-smoke.cloudflare-ddns-token
just secret-edit IanHollow.system.nixos.media-server-vm-smoke.vaultwarden-env
just secret-edit IanHollow.system.nixos.media-server-vm-smoke.vpn-gluetun-env
just secret-edit IanHollow.system.nixos.media-server-vm-smoke.qbittorrent-env
just secret-edit IanHollow.system.nixos.media-server-vm-smoke.pihole-env
just secret-edit IanHollow.system.nixos.media-server-vm-smoke.homebridge-env
just secret-edit IanHollow.system.nixos.media-server-vm-smoke.scrypted-env
```

## Required secrets

### `cloudflare-ddns-token`

Used by:

- `services.ddclient` via `configs/nixos/media-server/modules/exposure.nix`

What it should contain:

```text
<cloudflare api token>
```

How to get it:

1. Open Cloudflare dashboard.
2. Go to `My Profile` -> `API Tokens`.
3. Create a custom token with:
   - `Zone` -> `DNS` -> `Edit`
   - `Zone` -> `Zone` -> `Read`
   - Scope it only to your media-server zone.
4. Copy the token once and store it with `just secret-edit`.

### `vaultwarden-env`

Used by:

- `modules/nixos/server/media/vaultwarden.nix`

Recommended contents:

```env
ADMIN_TOKEN=REPLACE_WITH_LONG_RANDOM_ADMIN_TOKEN
DOMAIN=https://vault.example.com
SIGNUPS_ALLOWED=false
```

How to get values:

- `ADMIN_TOKEN`
  - Generate locally with one of:

```bash
openssl rand -base64 48
python - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
```

- `DOMAIN`
  - Use the final public Vaultwarden URL behind Traefik/Cloudflare.

Optional later values you may want to add:

- SMTP settings
- `PUSH_ENABLED`
- websocket tuning

### `vpn-gluetun-env`

Used by:

- `modules/nixos/server/media/torrent-vpn.nix`

Recommended contents for Mullvad WireGuard:

```env
VPN_SERVICE_PROVIDER=mullvad
VPN_TYPE=wireguard
WIREGUARD_PRIVATE_KEY=REPLACE_WITH_MULLVAD_PRIVATE_KEY
WIREGUARD_ADDRESSES=REPLACE_WITH_MULLVAD_ADDRESS_CIDR
SERVER_COUNTRIES=United States
TZ=America/New_York
DOT=off
```

How to get it from Mullvad:

1. Log in to Mullvad.
2. Generate a WireGuard configuration.
3. Download the config file.
4. Copy these values:
   - `PrivateKey` -> `WIREGUARD_PRIVATE_KEY`
   - `Address` -> `WIREGUARD_ADDRESSES`
5. Pick your preferred exit region and set one of:
   - `SERVER_COUNTRIES=`
   - optionally `SERVER_CITIES=`
   - optionally `SERVER_HOSTNAMES=`

Notes:

- Mullvad no longer supports port forwarding.
- The current production design isolates qBittorrent behind Gluetun.

### `qbittorrent-env`

Used by:

- `modules/nixos/server/media/torrent-vpn.nix`

Recommended contents:

```env
PUID=0
PGID=0
TZ=America/New_York
WEBUI_PORT=8080
UMASK=002
```

How to get it:

- No external provider is needed.
- Set your timezone.
- After first boot, log into qBittorrent and rotate the admin password in the UI.

### `pihole-env`

Used by:

- the Pi-hole container module

Recommended contents:

```env
TZ=America/New_York
PIHOLE_UID=0
PIHOLE_GID=0
WEBPASSWORD=REPLACE_WITH_PIHOLE_ADMIN_PASSWORD
```

How to get values:

- `WEBPASSWORD`
  - generate with `openssl rand -base64 24` or similar.

### `homebridge-env`

Used by:

- the Homebridge container module

Recommended starter contents:

```env
TZ=America/New_York
HOMEBRIDGE_CONFIG_UI=1
HOMEBRIDGE_CONFIG_UI_PORT=8581
```

How to get it:

- No external account is required for the base env.
- Add plugin-specific API keys later only if a Homebridge plugin requires them.

### `scrypted-env`

Used by:

- the Scrypted container module

Recommended starter contents:

```env
TZ=America/New_York
SCRYPTED_WEBHOOK_UPDATE_AUTHORIZATION=REPLACE_WITH_RANDOM_TOKEN
```

How to get values:

- `SCRYPTED_WEBHOOK_UPDATE_AUTHORIZATION`
  - generate locally with `openssl rand -hex 32`.

Add any camera/provider-specific secrets later if your Scrypted plugins need
them.

## Optional secrets

### `cloudflared-credentials`

Only needed if you enable `my.media.services.cloudflared.enable = true;`

How to get it:

1. Create a Cloudflare Tunnel.
2. Download the tunnel credentials JSON.
3. Store the raw JSON as the secret content.

### `cloudflared-cert`

Only needed if you enable tunnel-based cloudflared auth/cert flows.

How to get it:

1. Run `cloudflared tunnel login` on a trusted machine.
2. Store the generated cert content as the secret.

## Which values are not secrets

These belong in `configs/nixos/media-server/modules/site.nix`, not in agenix:

- domain names
- hostnames
- local LAN address
- disk IDs
- Cloudflare tunnel UUID
- Cloudflare Access audience tag

They are configuration values, not secrets.

## VM host keys already fetched

The VM qcow images currently contain these SSH host public keys and the VM host
configs have been updated to use them as the primary agenix recipients:

- `media-server-vm-parity`
  - `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYXqoCXD8+NQopmMXG0VJ1VkqkXUqFGwIYyR7b8kliA`
- `media-server-vm-smoke`
  - `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWJYXhsmU3IU+wIX5aF7rwb6ckGu8WZSGWh250e4gO6`

Your MacBook home SSH public key is also kept as an extra agenix recipient so
you can still edit and re-encrypt secrets locally.
