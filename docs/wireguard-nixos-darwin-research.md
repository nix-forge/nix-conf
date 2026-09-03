# WireGuard on NixOS and nix-darwin

Research date: 2026-09-02

## Scope

This note compares system-wide WireGuard clients on NixOS and macOS. The target
Mac is a roaming laptop that should use a home WireGuard endpoint away from one
trusted Wi-Fi network and disconnect on that network. This research does not
reproduce the private key or trusted SSID. The implementation keeps those two
values encrypted while declaring the non-secret tunnel fields in local Nix.

The repository pins Nixpkgs at
[`9fbb54b3`](https://github.com/NixOS/nixpkgs/tree/9fbb54b33e91ee4ca368e35a78e0613c720600b3)
and nix-darwin at
[`4cff07de`](https://github.com/nix-darwin/nix-darwin/tree/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48).
The findings below refer to those revisions rather than an unpinned option
search result.

## Recommendation

There is no single best front end on both operating systems.

On a NixOS server or a host already owned by systemd-networkd, use
`networking.wireguard.interfaces` with `networking.wireguard.useNetworkd = true`.
It uses Linux's in-kernel implementation, accepts keys through files, passes
those files to networkd as credentials, and supports routing tables, route
metrics, firewall marks, and periodic endpoint refresh. The in-kernel
implementation is the fast, well-integrated WireGuard implementation; upstream
explicitly recommends it over `wireguard-go` on Linux.
([NixOS interface options](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/nixos/modules/services/networking/wireguard.nix#L38-L219),
[networkd credential and refresh implementation](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/nixos/modules/services/networking/wireguard-networkd.nix#L35-L114),
[wireguard-go platform guidance](https://git.zx2c4.com/wireguard-go/about/))

On a roaming NixOS desktop, use NetworkManager's native WireGuard profile
support. It needs no VPN plugin, integrates routing and DNS with the active
network, and exposes the tunnel to `nmcli` and desktop controls. NetworkManager
can import a standard WireGuard file, and its dispatcher receives link and
connectivity events. Those are the right pieces for an off-trusted-Wi-Fi
policy. Store the imported profile only in root-readable runtime or system
connection storage, never in a Nix-generated file containing a private key.
([NetworkManager WireGuard support](https://networkmanager.dev/docs/vpn/),
[WireGuard settings and automatic default-route handling](https://networkmanager.dev/docs/api/latest/settings-wireguard.html),
[dispatcher events](https://networkmanager.dev/docs/api/latest/NetworkManager-dispatcher.html),
[WireGuard import API](https://networkmanager.dev/docs/libnm/latest/libnm-nm-conn-utils.html),
[keyfile permissions](https://networkmanager.dev/docs/api/latest/nm-settings-keyfile.html))

On macOS, the official WireGuard app remains the most complete client. It uses
an `NEPacketTunnelProvider`, appears in the system VPN UI, and programs Apple's
ordered on-demand rules. Its own source implements "except specific SSIDs" and
adds a connect rule for Ethernet on macOS. That exactly matches the requested
roaming policy and lets the OS react to network changes and sleep/wake.
([packet tunnel provider](https://git.zx2c4.com/wireguard-apple/tree/Sources/WireGuardNetworkExtension/PacketTunnelProvider.swift),
[WireGuard on-demand implementation](https://git.zx2c4.com/wireguard-apple/tree/WireGuard/WireGuard/Tunnel/ActivateOnDemandSetting.swift?h=am/wgkit-types-subtarget&id=7a450089c0a0cda91b87c567c441af305ae12a58),
[Apple on-demand ordering](https://developer.apple.com/documentation/networkextension/nevpnmanager/ondemandrules),
[Apple SSID matching](https://developer.apple.com/documentation/networkextension/neondemandrule/ssidmatch))

That app is not packaged in Nixpkgs. The official macOS binary is distributed
through the Mac App Store. Building the source is not a normal pure Nix build:
upstream requires an Xcode project with a developer team and bundle IDs, and
the app and extension require Network Extension and app-group entitlements.
Apple ties available macOS capabilities to the signing certificate and program
membership. A self-built, locally signed package would make signing and
provisioning part of routine system rebuilds. That is worse operationally than
the App Store build.
([official installation page](https://www.wireguard.com/install/),
[upstream build instructions](https://github.com/WireGuard/wireguard-apple#building),
[developer configuration and entitlements](https://git.zx2c4.com/wireguard-apple/commit/Sources?id=ec574085703ea1c8b2d4538596961beb910c4382),
[Apple capability matrix](https://developer.apple.com/help/account/reference/supported-capabilities-macos))

If Nix ownership is a hard requirement, use Nixpkgs `wireguard-tools` and
`wireguard-go` through nix-darwin's `networking.wg-quick` module plus a small
roaming controller. This is the best
Nix-owned option, but it is not as feature-rich as the official app. It creates
a userspace `utun` interface and needs its own trusted-network controller. It
has no native VPN menu, no Apple on-demand rules, and no Network Extension
lifecycle. Upstream also documents that Darwin has no fwmark support and that
the userspace implementation lacks sticky sockets.
([Nixpkgs Darwin wrapper](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/pkgs/by-name/wi/wireguard-tools/package.nix#L66-L70),
[wireguard-go macOS limitations](https://git.zx2c4.com/wireguard-go/about/))

For this MacBook, I would implement that Nix-owned path because the user asked
to leave the App Store, but I would stage it carefully and keep the existing
app installed until the replacement passes manual tests away from home.

## Option comparison

| Host and front end | Data path | Routing and DNS | Roaming UX | Secret handling | Verdict |
| --- | --- | --- | --- | --- | --- |
| NixOS `networking.wireguard` plus networkd | Linux kernel | Fully declarative; route table, metric, fwmark, endpoint refresh | Good for fixed hosts; little desktop UI | `privateKeyFile` and networkd credentials | Best for servers and networkd hosts |
| NixOS NetworkManager native profile | Linux kernel | NetworkManager owns routes and DNS; automatic full-tunnel policy routing | Best Linux laptop UX; GUI, `nmcli`, dispatcher | Import at runtime to a root-only keyfile | Best for roaming NixOS laptops |
| NixOS `networking.wg-quick` | Linux kernel | Faithful `wg-quick`; full config import, hooks, DNS, automatic table logic | Simple systemd control; no native desktop policy | External `configFile` is copied to a private service temp directory | Best compatibility path for an existing file |
| Official WireGuard macOS app | Network Extension packet tunnel using WireGuardKit | Scoped through Apple's VPN APIs | Best macOS UX and native on-demand SSID exclusion | App-managed tunnel storage and system VPN preferences | Best macOS client, but App Store or self-signed Xcode build |
| nix-darwin `networking.wg-quick` | `wireguard-go` over `utun` | `wg-quick` mutates routes and every network service's DNS | Basic launchd service; no SSID policy | External private and preshared key files, but no whole-file import | Useful base, insufficient by itself |
| Custom nix-darwin roaming wrapper | `wireguard-go` over `utun` | Same as `wg-quick`, with health-check rollback | Automatic off-trusted-Wi-Fi behavior and manual controls | Private key and SSID stay in runtime secret files | Best Nix-owned macOS compromise |

WireGuard itself is a sound choice. Upstream documents its fixed modern
cryptographic suite and small attack surface. On Linux, keeping the packet path
in the kernel is also the performance choice. Avoid quoting the old WireGuard
benchmark page as current evidence; upstream now labels those measurements old
and poorly conducted.
([WireGuard protocol overview](https://www.wireguard.com/),
[benchmark caveat](https://www.wireguard.com/performance/))

## NixOS details

### Fixed hosts

The native NixOS module has the broadest low-level controls. It supports
namespaces, `fwMark`, custom route tables, route metrics, MTU, dynamic endpoint
refresh, file-backed private keys, and file-backed preshared keys. With
networkd, NixOS deliberately rejects inline private and preshared keys to keep
them out of the Nix store. It loads the external files as systemd credentials.
([native option definitions](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/nixos/modules/services/networking/wireguard.nix#L38-L219),
[networkd secret assertions](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/nixos/modules/services/networking/wireguard-networkd.nix#L149-L220),
[credential loading](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/nixos/modules/services/networking/wireguard-networkd.nix#L234-L246))

Use a nonzero `dynamicEndpointRefreshSeconds` when a home endpoint is a DNS
name whose address may change. The kernel does not resolve DNS after initial
setup; the NixOS option exists to refresh it. Do not enable persistent
keepalive by habit. WireGuard's NixOS option describes 25 seconds as useful
when a peer behind NAT must remain reachable, but most clients generate traffic
and do not need it.
([endpoint warning and refresh option](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/nixos/modules/services/networking/wireguard.nix#L308-L345),
[keepalive semantics](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/nixos/modules/services/networking/wireguard.nix#L348-L369))

### Roaming laptops

NetworkManager 1.16 and later supports WireGuard as a native connection type,
not a VPN plugin. For a full tunnel, it can put the default route in a dedicated
table and add policy rules using the same improved routing scheme as
`wg-quick`. A dispatcher can activate or deactivate the profile on `up`,
`down`, and `connectivity-change` events. Dispatcher scripts run serially and
may see stale queued events, so the script must re-read current state under a
lock before changing the tunnel.
([native support](https://networkmanager.dev/docs/vpn/),
[automatic route behavior](https://networkmanager.dev/docs/api/latest/settings-wireguard.html),
[dispatcher sequencing warning](https://networkmanager.dev/docs/api/latest/NetworkManager-dispatcher.html))

Do not place `wireguard.private-key` in
`networking.networkmanager.ensureProfiles` or any other Nix-generated text.
Import the external profile at activation or first use, into
`/etc/NetworkManager/system-connections` or
`/run/NetworkManager/system-connections`, with mode `0600` and root ownership.
NetworkManager refuses keyfiles that other users can read or write.
([NetworkManager keyfile rules](https://networkmanager.dev/docs/api/latest/nm-settings-keyfile.html))

`networking.wg-quick.interfaces.<name>.configFile` remains the least surprising
way to consume an existing file without translating it. The pinned module has
`autostart`, imports a config file, uses a private systemd temporary directory,
and runs `wg-quick down` on stop. Prefer it when fidelity to the supplied file
matters more than desktop controls.
([pinned NixOS wg-quick options](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/nixos/modules/services/networking/wg-quick.nix#L33-L166),
[service implementation](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/nixos/modules/services/networking/wg-quick.nix#L289-L410))

## What nix-darwin already provides

Pinned nix-darwin now has `networking.wg-quick.interfaces`. It supports address,
DNS, MTU, routes, hooks, peers, a private key file, preshared key files, and an
`autostart` switch. It installs Nixpkgs `wireguard-tools` and `wireguard-go`,
writes `/etc/wireguard/<name>.conf`, and creates a launchd daemon for autostarted
interfaces.
([nix-darwin options](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/services/wg-quick.nix#L8-L124),
[generated profile](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/services/wg-quick.nix#L129-L185),
[launchd and packages](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/services/wg-quick.nix#L187-L230))

It does not meet this MacBook's full requirements:

- It has no whole `configFile` option, so using the supplied profile requires
  translating its non-secret fields into Nix. Endpoint and topology data would
  then be public in the repository and Nix store.
- `autostart` means boot-time launch. `KeepAlive.NetworkState` knows only that
  some network is available. It cannot express "except this SSID."
- The service has no activation health test or timed rollback. A syntactically
  valid full-tunnel profile can take over default routes even when its peer is
  unreachable.
- It exposes no native VPN menu or Apple on-demand state.

The upstream Darwin `wg-quick` script itself is reasonably careful. It warns
about group/world-readable profiles, selects an available `utun`, calculates
MTU, preserves an endpoint route outside a full tunnel, monitors route changes,
and restores DNS on shutdown. For a default route it installs two `/1` routes.
([profile and `utun` setup](https://git.zx2c4.com/wireguard-tools/tree/src/wg-quick/darwin.bash#n575),
[endpoint routing](https://git.zx2c4.com/wireguard-tools/tree/src/wg-quick/darwin.bash#n772),
[DNS and route monitor](https://git.zx2c4.com/wireguard-tools/tree/src/wg-quick/darwin.bash#n823),
[default-route implementation](https://git.zx2c4.com/wireguard-tools/tree/src/wg-quick/darwin.bash#n877))

There is still a sharp edge: DNS is changed with `networksetup` across all
network services. If the service is killed without its cleanup path running,
stale DNS can outlive the tunnel. The route monitor also contains an upstream
TODO for endpoint changes. A custom controller must always call `wg-quick down`
and should keep a DNS recovery command available.
([DNS mutation and restore](https://git.zx2c4.com/wireguard-tools/tree/src/wg-quick/darwin.bash#n823),
[route-monitor TODO](https://git.zx2c4.com/wireguard-tools/tree/src/wg-quick/darwin.bash#n852))

## Required custom nix-darwin module

The generic module should wrap Nixpkgs tools rather than fork WireGuard. Keep it
under the repository's generic Darwin modules. The MacBook's local file should
declare the public tunnel fields and name the private-key and SSID secret paths.

Recommended interface:

```nix
networking.wg-quick.interfaces.home-vpn = {
  autostart = false;
  address = [ "192.0.2.2/32" ];
  privateKeyFile = "/run/private/wireguard/private-key";
  peers = [ { /* public peer and route data */ } ];
};
services.wireguardRoaming = {
  enable = true;
  interfaceName = "home-vpn";
  trustedSSIDFile = "/run/private/wireguard/trusted-ssid";
  autoConnect = true;
  activationTimeoutSeconds = 15;
};
```

The two private file values are strings, not Nix path literals. The module must
never read either one while evaluating the configuration. It should reject
`/nix/store` private-key and SSID paths, require root ownership and mode `0600`
or stricter at runtime, and avoid printing their content in logs.

The controller should have these behaviors:

1. Serialize every transition with a lock, then re-read current network state.
2. Treat missing secrets, no Wi-Fi, an unreadable SSID, a captive portal, or
   ambiguous network state as `down`. This is a fail-open policy for ordinary
   Internet access and a fail-closed policy for tunnel activation.
3. On the trusted SSID, run `wg-quick down` if the tunnel is present.
4. Away from the trusted SSID, first confirm the ordinary network is reachable.
   Then run `wg-quick up` for the non-autostart nix-darwin interface.
5. Provoke tunnel traffic, wait no more than the configured timeout for a fresh
   handshake and the health check, and run `wg-quick down` on failure.
6. Reconcile after network changes and wake. A small compiled Swift helper can
   use Core WLAN event callbacks and System Configuration notifications. If a
   shell implementation is chosen first, use a modest launchd interval as a
   fallback and document the energy and latency cost. Apple documents Core WLAN
   event registration and System Configuration network-state notifications.
   ([Core WLAN](https://developer.apple.com/documentation/CoreWLAN),
   [System Configuration dynamic store](https://developer.apple.com/documentation/systemconfiguration/scdynamicstore-gb2))
7. Provide `wireguard-roaming status`, `up`, `down`, `reconcile`, and
   `recover-dns`. `down` must always work without reading the SSID file.
8. Do not add a packet-filter kill switch for this use case. The priority is
   retaining Internet access when the home peer or controller fails. The trade
   is explicit: traffic uses the ordinary network while the VPN is unavailable.

SSID access from a custom helper may require user authorization or an
entitlement depending on the API and packaging. Apple lists an Access Wi-Fi
Information entitlement and treats location as protected data. If the helper
cannot retrieve the SSID, it must leave the tunnel down and explain the required
permission without logging the expected or observed name.
([System Configuration entitlement listing](https://developer.apple.com/documentation/systemconfiguration),
[Core WLAN SSID API](https://developer.apple.com/documentation/corewlan/cwinterface),
[location authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services))

## Safe rollout for the MacBook

Do not make the first switch automatic. A full-tunnel mistake can leave the
machine online at layer 2 while all useful traffic points into a dead `utun`.

1. Extract the supplied profile's private key into the existing runtime secret
   system with root ownership and mode `0400`. Put its public tunnel fields in
   the host-local Nix configuration. Remove the Downloads copy only after
   confirming the encrypted key and recovery material exist.
2. Install the Nix tools and module with `autoConnect = false`. Keep the App
   Store app installed but disable its on-demand activation so two clients
   cannot own the same routes and DNS.
3. Test `up`, handshake, DNS, IPv4, IPv6, access to the intended home resource,
   `down`, DNS restoration, sleep/wake, and switching between two non-home
   networks. A profile that only contains `0.0.0.0/0` is not an IPv6 full
   tunnel; either route `::/0` through the peer or consciously accept IPv6
   bypass.
4. Test the trusted-network branch at home. It must remain down. Also test the
   unknown-SSID branch by denying SSID permission; it must remain down.
5. Enable automatic reconciliation. Confirm that a failed health check removes
   the `/1` routes and restores DNS within the timeout.
6. Only then remove the App Store app. Keep the manual `down` and `recover-dns`
   commands available from a shell that does not depend on tunnel DNS.

This rollout favors recovery over a VPN kill switch. That is appropriate for a
home egress tunnel whose stated hard requirement is not losing Internet access.

## Repository placement

Generic implementation belongs under `modules/darwin`, alongside other
machine-level nix-darwin modules. The MacBook enablement and runtime secret
references belong under `hosts/darwin/macbook-pro-m4/local`. Only the private
key and SSID belong in the runtime secret system. Public tunnel fields belong
in the host-local Nix file.
