{
  imports = [
    ./options.nix
    ./system.nix
    ./networking.nix
    ./traefik.nix
    ./arr.nix
    ./jellyfin.nix
    ./jellyseerr.nix
    ./vaultwarden.nix
    ./ddns-cloudflare.nix
    ./torrent-vpn.nix
    ./containers.nix
  ];
}
