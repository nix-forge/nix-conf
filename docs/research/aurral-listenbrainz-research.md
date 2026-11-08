# ListenBrainz connections in Aurral

Reviewed: 2026-09-26. Scope: Aurral 2.9.1 with this repository's MusicBrainz,
ListenBrainz discovery and connection patches, and Navidrome's documented APIs.

## Answer

Two defects caused the connection prompt to lead nowhere useful. The discovery
patch renamed the Last.fm banner to ListenBrainz but left it pointing at Connect
without adding ListenBrainz controls. The authenticated bootstrap also read the
stripped login identity instead of the persisted listening-history profile,
reporting an existing profile as unconfigured.

The connection patch adds a ListenBrainz card and a dialog at
`/settings/connect?integration=listenbrainz`. All ListenBrainz connection
actions open this dialog. Bootstrap reads the current account's saved profile.
Saving a connection refreshes the profile, discovery and bootstrap caches.

Public history and scrobbling have separate status. A username selects public
history, charts and recommendations; a validated private user token permits
submission of completed plays. Token linking sets the history profile to the
verified account in the same transaction. Disconnecting scrobbling retains the
public history profile. The existing encrypted connection store holds tokens;
public status responses contain no token.

## Findings and sources

ListenBrainz token validation returns `valid` and `user_name`; HTTP 200 alone is
insufficient. Recommendation reads can return 204 before recommendations exist.
Neither an empty history nor pending recommendations establishes a broken
connection.
[Core API](https://listenbrainz.readthedocs.io/en/latest/users/api/core.html),
[recommendation API](https://listenbrainz.readthedocs.io/en/latest/users/api/recommendation.html).

ListenBrainz requires an identifying User-Agent and at most one request per
second. The local client previously used 250 ms spacing. The connection patch
adds the application identity, serializes requests with one-second spacing, and
applies a shared cooldown after 429 using the upstream reset header. Reads have
bounded retries; submission writes are not automatically repeated.
[ListenBrainz API requirements](https://listenbrainz.readthedocs.io/en/latest/users/api/index.html).

The submission client previously placed a release-group identifier in
`release_mbid`. It now uses `release_group_mbid` for this value and sends
`release_mbid` only when a release identifier is known. The earlier metadata
patch separately preserves recording, release and release-group identities in
library metadata and file tags.

The managed Aurral administrator can use the same sealed ListenBrainz identity
already configured for Navidrome. Bootstrap supplies an expected account name;
the server rejects a different token owner before changing the connection. A
private fingerprint avoids validating an unchanged token on every restart. Other
Aurral users retain their own connections. Navidrome keeps its separate per-user
token link; it does not inherit an Aurral session.
[Navidrome scrobbling](https://www.navidrome.org/docs/usage/features/scrobbling/).

MetaBrainz is a collection of projects, not one account toggle:

| Integration                                                           | Connection requirement                                          | Scope                                                                        |
| --------------------------------------------------------------------- | --------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| ListenBrainz history, charts, recommendations and generated playlists | Public username and upstream data availability                  | Existing discovery patch; Connect configures the profile.                    |
| ListenBrainz scrobbling                                               | Validated per-user token                                        | Aurral and Navidrome have separate submission paths.                         |
| MusicBrainz artist, recording and release metadata                    | Public API, identifying client and rate limiting                | Existing metadata integration; no ListenBrainz token required.               |
| Cover Art Archive                                                     | Correct release or release-group identifier; artwork must exist | Existing backend artwork integration.                                        |
| AcousticBrainz                                                        | Historical recording data, when available                       | New data collection stopped in 2022; no new integration is implemented here. |
| Other MetaBrainz projects and write APIs                              | Project-specific implementation and permissions                 | Outside this connection repair.                                              |

[MusicBrainz API](https://musicbrainz.org/doc/MusicBrainz_API),
[Cover Art Archive API](https://musicbrainz.org/doc/Cover_Art_Archive/API),
[AcousticBrainz](https://acousticbrainz.org/).

## Validation and limits

The authenticated bootstrap regression failed against the original code and
passes with the connection patch. Disposable API tests also verify rejection of
`valid: false` and a mismatched token owner, atomic profile alignment,
token-free status responses, retained history after unlink, identifying headers,
one-second request spacing, 429 recovery and correct MusicBrainz entity fields.
Submission tests intercept the network and do not create public listening data.

Four bootstrap tests passed, covering sealed identity linking, unchanged-token
reuse and failure to mark a mismatched account ready. Package installation
checks passed alongside the existing discovery and real-file metadata checks.
The package's all-systems evaluation and the desktop system build passed. The
first desktop build rejected bootstrap lines longer than the Python writer's
limit; this was corrected before deployment.

A live isolated browser verified the Connect deep link, card interaction,
password field clearing, absence of the false homepage prompt and absence of
JavaScript exceptions. Authenticated profile, bootstrap and scrobbling status
agreed. Public ListenBrainz reads succeeded; collaborative recommendations
returned 204 and created-for playlists were empty. The existing discovery
fallback still returned recommendations and editorial playlists.

Both managed Navidrome listener connections used the same sealed token. The
importer was enabled, its account mappings matched, and it reported no stored
error. No generated ListenBrainz playlists were available to exercise an actual
import. This validates configuration and connection identity, not a completed
playlist import.

Aurral and the downloaders remained in the VPN namespace after deployment.
Runtime checks verified the VPN exit, confined DNS, blocked host resolver IPC,
tunnel-only IPv6, tunnel failure dependencies and loopback API bridges. These
checks establish the tested service boundaries, not a universal anonymity
promise for every application on the host.

A saved public username is configuration, not continuous proof of upstream
availability. Generated playlists and recommendations depend on ListenBrainz's
processing and the recordings present in the local library. AcousticBrainz,
other MetaBrainz projects, two-person importer ownership and the whole universe
of MetaBrainz write APIs are not validated by this repair.

## Implementation references

- [Connection patch](../../pkgs/pkgs/by-name/au/aurral/listenbrainz-connect.patch)
- [API regressions](../../pkgs/pkgs/by-name/au/aurral/listenbrainz-connect.test.mts)
- [Bootstrap](../../hosts/nixos/desktop/local/homelab/music/scripts/bootstrap_aurral.py)
- [Music discovery investigation](media-music-discovery-research.md)
- [Spotify and MetaBrainz](../operations/spotify-metabrainz.md)
