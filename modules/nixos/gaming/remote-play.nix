{ lib, ... }:
let
  privateIPv4 = "10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16";
  sunshineTcpPorts = "47984, 47989, 47990, 48010";
  sunshineUdpPorts = "47998, 47999, 48000, 48002, 48010";
in
{
  # Sunshine is the host; Moonlight on the MacBook is the client. The desktop
  # captures the same physical Hyprland output used at the console.
  services.sunshine = {
    enable = true;
    autoStart = true;
    openFirewall = false;

    # Hyprland's wlroots capture path can capture the physical output without
    # giving the streaming process CAP_SYS_ADMIN solely for KMS capture.
    capSysAdmin = false;

    settings = {
      sunshine_name = "desktop";
      encoder = "nvenc";
      capture = "wlr";

      # This host has both AMD and NVIDIA render nodes.  Automatic selection
      # chooses the AMD node first, which cannot create an NVENC session and
      # makes Sunshine abort the stream.  Keep capture and NVENC on the RTX
      # 4070's stable render node (PCI 01:00.0).
      adapter_name = "/dev/dri/by-path/pci-0000:01:00.0-render";

      # Do not create WAN port mappings.  Moonlight discovers the host by the
      # configured desktop address, so Avahi remains disabled on this host.
      upnp = "disabled";
      address_family = "both";
      origin_web_ui_allowed = "lan";

      # Sunshine 2026.516 added strict CSRF origin validation.  The Web UI is
      # intentionally reachable only from the LAN, but browser requests that
      # create the initial account must also name their exact HTTPS origin.
      # Keep this finite and local rather than allowing arbitrary LAN origins.
      csrf_allowed_origins = "https://desktop:47990,https://desktop.local:47990,https://192.168.10.178:47990";

      # Modern Moonlight clients support encrypted Sunshine streams.  Require
      # that protection even on the LAN; codec choice stays automatic so the
      # NVIDIA encoder and Apple decoder can negotiate the best common format.
      lan_encryption_mode = 2;
      wan_encryption_mode = 2;
    };

  };

  # NixOS installs this user unit for every graphical account; it must never
  # start in the greeter's manager.
  systemd.user.services.sunshine = {
    unitConfig.ConditionUser = "ianmh";
  };

  # Sunshine's generated firewall integration opens these ports to every
  # source.  Keep it disabled and permit the documented control, video, audio,
  # RTSP, and web-UI ports only from RFC1918 IPv4 and IPv6 ULA networks.
  networking.firewall.extraInputRules = lib.mkAfter ''
    ip saddr { ${privateIPv4} } tcp dport { ${sunshineTcpPorts} } accept comment "allow Sunshine from private IPv4 networks"
    ip saddr { ${privateIPv4} } udp dport { ${sunshineUdpPorts} } accept comment "allow Sunshine from private IPv4 networks"
    ip6 saddr fc00::/7 tcp dport { ${sunshineTcpPorts} } accept comment "allow Sunshine from IPv6 ULA networks"
    ip6 saddr fc00::/7 udp dport { ${sunshineUdpPorts} } accept comment "allow Sunshine from IPv6 ULA networks"
  '';
}
