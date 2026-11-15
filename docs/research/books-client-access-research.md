# Book and audiobook access across iPhone and desktop

Reviewed: 2026-10-01. Scope: the desktop's Audiobookshelf, Komga, and
BookOrbit 3.2.0 deployment; current iPhone and desktop clients.

## Answer

Use the existing HTTPS sites in a desktop browser. For one app across ebooks,
comics, and audiobooks, trial the
[official BookOrbit iPhone and iPad app](https://apps.apple.com/us/app/bookorbit-the-official-app/id6811807346)
against this server. It supports offline downloads and syncs its own reading
state, but a real client and media trial is still needed. If you prefer the
established specialist readers, use
[AudioBooth](https://apps.apple.com/us/app/audiobooth-audiobooks-player/id6753017503)
for audiobooks and a Komga client for EPUBs and comics. AudioBooth is an
open-source App Store client with offline downloads, CarPlay, and Audiobookshelf
progress sync. Audiobookshelf's own iOS app remains in beta and its TestFlight
is full according to the [upstream project](https://github.com/advplyr/audiobookshelf).
The [Audiobookshelf community client list](https://audiobookshelf.org/docs/documentation/community/community-apps/)
explicitly warns that the server team does not test or maintain third-party
clients. For Komga,
[KMReader](https://komga.org/docs/guides/kmreader/) is the most direct client
to trial for both EPUB and comics: it uses Komga's API, downloads books, and
reports online and deferred offline progress synchronization. It requires
iOS 17 or later. These are source claims, not a hands-on comparison.

The official BookOrbit app covers EPUB, PDF, CBZ, CBR, audiobooks, and offline
downloads. It requires iOS or iPadOS 26 or later and a
[BookOrbit 3.0 or later server](https://github.com/bookorbit/bookorbit/releases/tag/v3.0.0),
which the pinned 3.2.0 server meets. Unlimited downloads and Apple Watch
listening are Premium features. Version 1.2.0 adds a native iPad layout.
[App Store version history](https://apps.apple.com/us/app/bookorbit-the-official-app/id6811807346).
The BookOrbit library remains read-only on this server.
The HTTPS gateway now admits the approved iPhone WireGuard client, but a real
book, app login, offline, and progress trial has not been completed.
[Local BookOrbit policy](../../hosts/nixos/desktop/local/homelab/book-discovery.nix),
[BookOrbit deployment steps](../operations/books-discovery-deployment.md).

## Practical paths

| Use | iPhone or iPad | Desktop | Sync boundary |
| --- | --- | --- | --- |
| Audiobooks | [AudioBooth](https://apps.apple.com/us/app/audiobooth-audiobooks-player/id6753017503); [Audiobookshelf iOS beta](https://audiobookshelf.org/docs/documentation/introduction/) if already enrolled | Audiobookshelf HTTPS web player | Audiobookshelf tracks listening progress per user across its clients. |
| EPUB and comics | [KMReader](https://komga.org/docs/guides/kmreader/) with the Komga server URL; use its manual offline policy first | [Komga web readers](https://komga.org/docs/guides/webreader-epub/) | Komga tracks progress per user; KMReader says offline changes upload on reconnect. |
| Comic-focused alternative | [Panels](https://komga.org/docs/guides/panels/) streams or downloads over OPDS; its OPDS connector requires a purchase or subscription | Komga web reader | Confirm progress with a sample title before depending on a third-party client. |
| Cross-format reading and requests | Official BookOrbit app through the approved LAN or WireGuard path | BookOrbit HTTPS site | BookOrbit syncs its own reading state; it does not continuously sync Audiobookshelf or Komga progress. |

Use the `https://` origin of the intended service and its own restricted reader
credentials. KMReader accepts that origin with either credentials or a Komga
API key. A generic OPDS 2 reader can use
`https://komga.<DOMAIN>/opds/v2/catalog`, but OPDS client behavior varies.
[KMReader setup](https://komga.org/docs/guides/kmreader/),
[Komga OPDS guide](https://komga.org/docs/guides/opds/),
[local access instructions](../operations/books-audiobooks-deployment.md).

For an iPhone shortcut to a web site, Safari can add the HTTPS page to the
Home Screen. This is a launch shortcut; it does not establish that a service's
web reader stores whole books for offline use. Prefer a client with an explicit
download feature before travel. [Apple Home Screen guide](https://support.apple.com/en-az/guide/iphone/iphea86e5236/26/ios/26),
[Audiobookshelf offline app feature](https://audiobookshelf.org/docs/documentation/introduction/),
[KMReader offline guide](https://komga.org/docs/guides/kmreader/).

## How seamless can it be?

Audiobookshelf, Komga, and BookOrbit each maintain their own account and
progress database. The same media files appearing in more than one library
do not make listening or reading position flow between those services. Using
one service consistently for a given title yields the dependable phone-to-
desktop resume path. A unified BookOrbit phone-to-web path still needs a real
client and media trial. The current deployment keeps
Audiobookshelf and Komga as the established players. [Audiobookshelf progress](https://audiobookshelf.org/docs/documentation/introduction/),
[Komga progress](https://komga.org/docs/guides/read-progress/),
[BookOrbit per-user progress](https://bookorbit.app/what-is-bookorbit),
[local service design](../operations/books-discovery-deployment.md).

BookOrbit also documents a cross-format position bridge **inside BookOrbit**
when one title has a media-overlay EPUB and matching standalone audio. It
does not claim to translate progress from Audiobookshelf or Komga. Ordinary
separate ebook and audiobook files therefore should not be expected to resume
at the same sentence. [BookOrbit read-along requirements](https://bookorbit.app/storyteller-read-aloud).

BookOrbit requests can cover ebooks, audiobooks, or comics, but one request
covers one medium. The desktop deployment now connects two vetted, VPN-routed
Prowlarr search sources for release discovery. It has no download client, so
requests are still manually fulfilled. Readers need `Request books` permission,
and the feature remains marked beta. [BookOrbit requests](https://bookorbit.app/book-requests/),
[local deployment](../operations/books-discovery-deployment.md).

## Private remote access

The HTTPS gateway admits only the configured home LAN and approved WireGuard
clients for Audiobookshelf, Komga, and BookOrbit. A phone away from home
therefore needs an approved VPN connection and working name resolution for the
private HTTPS origins. The server's VPN namespace for metadata lookups does not route or
protect an iPhone app's own traffic. Keep TLS certificate validation enabled
and use the private HTTPS names rather than a raw HTTP port. [Local network
boundary](../operations/books-audiobooks-deployment.md#network-boundary),
[BookOrbit sharing rule](../../hosts/nixos/desktop/local/homelab/book-discovery.nix),
[WireGuard iOS installation](https://www.wireguard.com/install/).

No client can promise that all DNS, IP, or reading activity stays undisclosed.
For example, BookOrbit's [iOS privacy policy](https://bookorbit.app/privacy/)
says Premium purchase status is checked with RevenueCat, optional network
text-to-speech sends selected text to a provider, and podcast playback can
contact publishers. A phone-side DNS and network check is needed before making
claims about that specific client and VPN configuration.

## Validation and limits

This is a 2026-10-01 review of official service documentation, official app
listings, and repository configuration. No iPhone or iPad app was installed or
tested; no nonempty book was played, downloaded, or resumed across devices.
The current media libraries are empty, and BookOrbit's approved phone access
has not been tested on the device. The next useful check is one EPUB, one CBZ/CBR, and one M4B
on the desktop and phone, with an offline segment and reconnect for each
selected client. Test the same account's resume point and inspect phone-side
DNS and network traffic over both home Wi-Fi and cellular VPN.
