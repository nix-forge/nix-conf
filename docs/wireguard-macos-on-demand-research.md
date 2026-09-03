# WireGuard on-demand behavior on macOS

Research date: 2026-09-02

## Decision

The nix-darwin WireGuard controller is fully standalone. It has no responder,
remote trust detector, desktop-host option, or cross-system dependency. Manual
control is the default. An optional always-on mode connects on every usable
network and still depends only on the Mac and the configured WireGuard peer.

The generic module does not automatically disconnect on a trusted Wi-Fi
network. With the existing `wg-quick` architecture, doing that securely would
require either location-sensitive SSID observation or a second trusted system.
Neither belongs in this module.

## Upstream behavior

WireGuard's Apple client is open source under the MIT license. Its macOS app
implements trusted-SSID behavior with Apple's VPN On Demand rules and a packet
tunnel Network Extension. The rules disconnect on configured Wi-Fi names, then
connect on other Wi-Fi networks and, when selected, Ethernet. macOS evaluates
the ordered policy as part of the VPN configuration.
([upstream source](https://git.zx2c4.com/wireguard-apple/about/),
[rule construction](https://github.com/WireGuard/wireguard-apple/blob/2fec12a6e1f6e3460b6ee483aa00ad29cddadab1/Sources/WireGuardApp/Tunnel/ActivateOnDemandOption.swift),
[Apple VPN On Demand rules](https://developer.apple.com/documentation/networkextension/vpn-on-demand-rules))

The editor uses CoreWLAN only to suggest the current network name. A user can
enter a name directly, after which the app stores it in `ssidMatch`. Reading the
current SSID through CoreWLAN is now subject to Apple's location-privacy policy.
([WireGuard SSID editor](https://github.com/WireGuard/wireguard-apple/blob/2fec12a6e1f6e3460b6ee483aa00ad29cddadab1/Sources/WireGuardApp/UI/macOS/View/OnDemandWiFiControls.swift),
[Apple DTS guidance](https://developer.apple.com/forums/thread/732431?answerId=758114022))

## Why the Nix module does not reproduce it

VPN On Demand controls a `NETunnelProviderManager`, not a `wg-quick` process.
The containing app and packet-tunnel extension require Apple signing,
provisioning, an app group, and the Network Extension entitlement. A public Nix
package cannot provide each user's signing identity, and upstream currently
distributes the macOS application through the Mac App Store rather than as a
vendor-signed standalone download.
([WireGuard build configuration](https://github.com/WireGuard/wireguard-apple/blob/2fec12a6e1f6e3460b6ee483aa00ad29cddadab1/Sources/WireGuardApp/Config/Developer.xcconfig.template),
[Apple Network Extension entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension),
[WireGuard installation page](https://www.wireguard.com/install/))

Gateway addresses, MAC addresses, DHCP values, DNS results, and public egress
addresses are not secure substitutes. They are supplied by or observable to
the network being judged and can collide or be spoofed. The module therefore
offers two explicit, honest policies:

- `autoConnect = false`: no launch daemon; use `wireguard-roaming up` and
  `wireguard-roaming down` manually.
- `autoConnect = true`: a standalone always-on launch daemon; no home-network
  exception.

This keeps the Mac build, runtime closure, and network policy independent of
every other declared machine.
