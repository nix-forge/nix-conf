# Noctalia Spotify album artwork

Research date: 2026-09-06. Source inspection uses the repository's pinned Noctalia v5 revision `f96a407deb109c9db6f29db75e6fe487a5289e02`, available locally at `/nix/store/c1589lf9ymzp29pldjifcwppa1brkwgs-source`.

The configuration checked at the start of this investigation set `shell.offline_mode = true` in `modules/home/desktop/config/noctalia.toml.in`. That setting prevents Noctalia from downloading uncached remote album covers. It explains how track names and playback controls can work while artwork is absent. Noctalia's documentation explicitly includes album art among the HTTP requests blocked by offline mode. [Shell configuration](https://docs.noctalia.dev/noctalia/configuration/shell/)

## What the pinned implementation does

Noctalia reads `mpris:artUrl` from each player's MPRIS metadata and exposes it as `art_url` through its own D-Bus API. The artwork resolver uses that URL directly for Spotify. Its URL rewriting and fallback logic targets Google and YouTube artwork, not Spotify. [Metadata ingestion and control API](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/dbus/mpris/mpris_service.cpp#L2776) [Artwork resolver](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/dbus/mpris/mpris_art.cpp#L81-L114)

The resolver accepts a local file immediately or looks for a nonempty cached download. Remote covers use `/tmp/noctalia-media-art/<hash>.img`, where the hash is C++ `std::hash<std::string_view>` of the URL. For an uncached remote cover it calls the shared HTTP client's download method. Offline mode makes that method return a deferred failure and log `download skipped in offline mode url=...`, before creating a download file or making a request. Failed requests leave the URL eligible for another attempt. [Cache and download resolution](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/dbus/mpris/mpris_art.cpp#L116-L163) [HTTP offline guard](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/net/http_client.cpp#L147-L153)

Configuration reload updates the shared HTTP client's offline flag. The Control Center media tab resolves artwork during updates and retries until an image loads. Reopening that tab after enabling HTTP should therefore allow the same track's cover to download without restarting Spotify. This is an inference from the source, to be checked against the running shell. [Reload callback](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/app/application_services.cpp#L505-L518) [Media-tab retries](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/control_center/tabs/media_tab.cpp#L890-L917)

The bar widget behaves differently. For an unchanged URL it retries decoding a cached file but does not restart the download itself. If only the bar remains blank after reload, reopen the media panel to populate the shared cache, or wait for a different cover URL. [Bar artwork updates](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/bar/widgets/media_widget.cpp#L330-L356)

## Fix and checks

Set `[shell] offline_mode = false` so Noctalia can fetch the cover URL. The pinned configuration exposes no separate option that allows album-art requests through offline mode. The media widget's `hide_album_art` option only controls presentation. Existing separate settings can continue to disable telemetry, public-IP lookup, weather, and exchange-rate updates. [Shell configuration](https://docs.noctalia.dev/noctalia/configuration/shell/) [Media widget options](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/bar/widgets/media_widget_definition.cpp)

Check a playing Spotify track with an uncached cover:

```bash
playerctl --player=spotify metadata mpris:artUrl
busctl --user call dev.noctalia.Mpris /dev/noctalia/Mpris dev.noctalia.Mpris GetActivePlayer
```

The first command reads Spotify's URL. The second checks that Noctalia received it. A matching remote URL plus the offline-mode warning isolates the failure after metadata ingestion. After reloading the corrected configuration and reopening the media panel, a nonempty file under `/tmp/noctalia-media-art` and a visible cover confirm the download and display path. Noctalia logs `artwork loaded` at debug level, or `artwork load failed` if decoding fails. [D-Bus API](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/dbus/mpris/mpris_service.cpp#L1262-L1292) [Media-tab diagnostics](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/control_center/tabs/media_tab.cpp#L900-L917)

## Other reported failures

Spotify users reported broken `https://open.spotify.com/image/...` MPRIS artwork URLs in 2020, with working equivalents at `https://i.scdn.co/image/...`. A 2024 report includes metadata already using `i.scdn.co`. These are firsthand user reports on Spotify's forum, not a current Spotify compatibility guarantee. Do not apply the old URL-rewriting workaround unless the live URL actually fails. [2020 cover URL report](https://community.spotify.com/t5/Desktop-Linux/MPRIS-cover-art-url-file-not-found/td-p/4920104) [2024 metadata sample](https://community.spotify.com/t5/Desktop-Linux/Command-Line-not-complet/td-p/6437482)

Noctalia issue #2950 describes an entirely missing player after startup with empty metadata. It does not establish a cause for a visible Spotify track that only lacks a cover. Source and configuration evidence support fixing the offline flag before considering an upstream update or a Spotify metadata proxy. [Noctalia issue #2950](https://github.com/noctalia-dev/noctalia/issues/2950)

## Local reproduction

No Spotify MPRIS player was active during the initial checks. An ephemeral MPRIS test player replayed a Spotify artwork URL from the shell's existing logs. With the original offline setting, Noctalia logged both `download skipped in offline mode` and `artwork unresolved`, and the artwork cache remained empty. This reproduces the failing shell path with an actual Spotify cover URL. It does not verify a newly playing Spotify track.

After changing the template to `offline_mode = false`, the generated settings passed `noctalia config validate`. The generated file differed from the active settings only in the offline flag and its comments. Applying that file and reloading the running shell made the same replay download and decode its cover in about 0.2 seconds. Noctalia logged `artwork loaded` for `/tmp/noctalia-media-art/4802248449305419593.img`. A second replay confirmed artwork loads in both the bar widget and Control Center media tab. The temporary test player and its dependencies were removed afterward. A full desktop build was unnecessary for this configuration-only verification.
