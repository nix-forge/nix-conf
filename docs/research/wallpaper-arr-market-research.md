# A credential-aware wallpaper source manager

## Recommendation

This is worth building, with a narrower promise than "an arr for wallpapers."
The useful product is a local-first source manager that turns approved remote
collections into a bounded, attributable local wallpaper library. It should
then hand a selected file to the user's existing wallpaper backend. It should
not be a general-purpose image scraper.

There is a real gap. Existing projects are good at setting, rotating, or
rendering wallpapers. Variety comes closest to a downloader and manager, but
its own README says the project is in maintenance mode. It downloads from
sources including Wallhaven, Unsplash, Bing, and Reddit, but it does not offer
a provider policy model, a credential vault, or a verifiable per-file rights
record. [Variety README](https://github.com/varietywalls/variety)

The project should start with Linux and Hyprland because that is where the
current configuration work has a concrete home. Keep the core independent of
Hyprland. A renderer adapter is replaceable. A source, policy, cache, and
metadata catalog are useful on GNOME, KDE, Xorg, macOS, and Windows too.

The first release should support local folders plus two no-credential,
machine-checkable sources: NASA SVS and Cleveland Museum of Art CC0. Add
Smithsonian Open Access as the first credentialed adapter. Do not promise
Unsplash, Pexels, Bing, or Wallhaven automation. Provider rules make a broad
"put in any API key" product both legally fragile and technically misleading.

## What already exists

| Project | What it does well | Why it does not replace this project |
| --- | --- | --- |
| [Variety](https://github.com/varietywalls/variety) | Local and remote image rotation, ratings, filters, tray controls, broad Linux-desktop support | Its README calls it maintenance mode. It combines source download with desktop control rather than providing a reusable source and policy service. |
| [Flying Bird Wallpaper](https://github.com/OXOYO/Flying-Bird-Wallpaper) | Windows and macOS app with images, video, dynamic wallpapers, several online sources, search, schedules, history, favourites, and custom plugins | It is a close functional competitor. Its existence says multi-source scheduling alone is not a differentiator. A provider-compliant local catalog is. |
| [wayper](https://github.com/yuukidach/wayper) | A Wallhaven-focused manager with automatic download, tag blocking, local curation, display-aware filtering, CLI, and GUI | Its deep single-source workflow is a good product reference. It does not solve multi-provider rights policy and should not make Wallhaven's user-uploaded catalogue appear automatically reusable. |
| [WPC](https://github.com/jkotra/wpc) | Lightweight CLI with separate fetch and change intervals, source plugins, minimum dimensions, startup mode, and hooks | It proves that a command-line automation baseline is useful. It does not provide a credential vault, admission policy, or durable per-file provenance. |
| [Waypaper](https://github.com/anufrievroman/waypaper) | A small GUI that selects local wallpapers, restores them, runs a slideshow, and delegates to many Wayland, Xorg, and macOS backends | It is a setter frontend. Its documented backends handle rendering, not source discovery, credentials, download policy, or provenance. |
| [HydraPaper](https://hydrapaper.gabmus.org/) | Local folders, favourites, command-line control, and separate wallpapers for several monitors | It manages an existing local collection. There is no remote source or account layer. |
| [awww](https://codeberg.org/LGFae/awww/src/branch/main/README.md) | Runtime image changes and transitions through wlroots layer-shell | It intentionally leaves time-based selection to another program. It has no catalog or fetch role. |
| [wpaperd](https://github.com/danyspin97/wpaperd) | Directory-based rotation, per-output configuration, pause controls, and accelerated transitions | Its upstream README says Hyprland is unsupported because of compositor-specific issues. It also assumes local files. |
| [mpvpaper](https://github.com/GhostNaN/mpvpaper) and [Linux Wallpaper Engine](https://github.com/Almamu/linux-wallpaperengine) | Video or Steam Wallpaper Engine rendering on wlroots-based Wayland | These are playback engines. Linux Wallpaper Engine requires assets from a user-owned Steam installation. Neither is a rights-aware source manager. |
| [Wallust](https://codeberg.org/explosion-mental/wallust) | Generates desktop colour schemes from the selected image | It is a useful hook after a wallpaper change, not a downloader or selector. |

This is a deliberately fragmented category. One tool owns rendering, another
owns selection, another derives colours, and download support is usually an
ad-hoc plugin. The source manager should cooperate with those tools instead of
trying to out-render them.

## The market is constrained by source rules

An API key is not permission to build a wallpaper collector. Source adapters
need an explicit admission policy, not a generic HTTP configuration page.

| Source | Automation position | Reason |
| --- | --- | --- |
| [NASA SVS](https://svs.gsfc.nasa.gov/help/) | Supported without credentials | SVS documents a JSON API, rich media metadata, and generally public-domain material. The adapter must still reject assets that carry a third-party restriction. |
| [Cleveland Museum of Art Open Access](https://openaccess-api.clevelandart.org/) | Supported without credentials | Its API exposes CC0 status, image URLs, dimensions, and file sizes. Restrict the adapter to records marked CC0. |
| [Smithsonian Open Access](https://www.si.edu/openaccess/faq) | Supported with a user API key | It offers CC0 assets but requires a key. Only admit media assets that are themselves identified as CC0. |
| [Wikimedia Commons](https://www.mediawiki.org/wiki/API:Imageinfo/en) | Supported later, with a strict licence profile | Imageinfo returns dimensions, MIME type, original URL, and extended metadata. Commons contains many licences, so default automation should accept only public-domain and CC0 files. Wikimedia asks non-interactive clients to use a descriptive User-Agent, cache results, request serially, and send `maxlag`. [API etiquette](https://www.mediawiki.org/wiki/API:Etiquette/en) |
| [Unsplash API](https://unsplash.com/documentation) | Do not support as a cached wallpaper source | Unsplash requires hotlinking rather than a stored local copy, requires a download-tracking call, and requires API compliance and attribution. Its API guidelines also prohibit wallpaper applications. A local rotating cache conflicts with that model. |
| [Pexels API](https://www.pexels.com/api/documentation/) | Do not support | Pexels requires an API key and explicitly prohibits making Pexels content available as a wallpaper app. |
| [Wallhaven](https://wallhaven.cc/help/api) | Manual import only | It can filter resolution and categories, but it is a community-uploaded collection without a dependable machine-readable reuse licence. Wallhaven also asks users not to run scraper or mass-download scripts. [FAQ](https://wallhaven.cc/faq) |
| [Pixabay API](https://pixabay.com/api/docs/) | Do not support without written provider approval | Its API has an API key and rate limits, but its terms prohibit standalone wallpaper distribution and competing services. A user key would not change that. [Pixabay terms](https://pixabay.com/service/terms/) |
| Bing daily image | Do not support as a source adapter | There is no documented wallpaper-content API with a reuse grant. Microsoft retired Bing Search APIs in 2025, so an undocumented archive endpoint is not a stable foundation. [Microsoft retirement notice](https://learn.microsoft.com/en-us/lifecycle/announcements/bing-search-api-retirement) |

That limitation is an argument for the project, not against it. People want
more than space photos. The hard part is finding a collection that can be
downloaded and reused safely, then retaining the information that proves why it
was admitted. Current wallpaper managers mostly leave that judgment to users.

## Where the project has value

The strongest user is someone who wants a changing desktop, cares where files
came from, and does not want a background process with their API token and full
home-directory access. NixOS and Hyprland users are a good first audience
because they already compose several small desktop tools. A normal Linux user
is a reasonable next step if the application has a GUI.

It has less value as a general consumer photo browser. Unsplash and Pexels
already own that experience, and their API rules shut down the tempting
shortcut of building a competing wallpaper client on top of their catalogues.
It also has little reason to replace Wallpaper Engine. Animated wallpaper
users already have renderer choices, and downloaded Workshop assets carry their
own platform and rights conditions.

The useful differentiators are:

* A source contract that records rights, origin, author, URL, retrieval time,
  dimensions, checksum, and source-specific restrictions for every accepted
  file.
* Quality profiles, such as "4K landscape SDR", "ultrawide", "art", or
  "nature", that filter against decoded image data rather than a provider's
  tags alone.
* Source composition. A user can weight NASA, museum art, their own folder,
  and a future credentialed collection, then rotate from one deduplicated local
  catalog.
* One source of truth that feeds `awww`, Hyprpaper, Waypaper, KDE, GNOME, or a
  static-file export. The renderer does not get network access or credentials.
* A review queue that makes licensing visible before an image enters the
  rotation. This is the difference between a pleasant desktop tool and a
  downloader that eventually surprises its user.

Success should be tested with real users, not GitHub stars. A credible pilot
would show that a fresh user can add NASA and CMA, connect Smithsonian, choose
a 4K policy, see why a candidate was rejected, and use the resulting files
offline. It should also prove that disabling a source revokes future fetches
without deleting user favourites.

## A product shape that will stay maintainable

Split the implementation into four parts with narrow interfaces.

1. **Source adapters** discover candidates and return normalised metadata. An
   adapter states whether it needs no credential, an API key, or an OAuth
   token. It also states its licence vocabulary, allowed hosts, rate limit,
   attribution requirements, and whether local retention is allowed.
2. **Policy and catalog** evaluate candidates. They enforce licence,
   orientation, decoded dimensions, pixel count, MIME type, byte ceiling,
   topic rules, duplicate detection, per-source quotas, and a global disk
   budget. The catalog stores immutable sidecars, not only filenames.
3. **Fetcher and cache** download one approved item at a time to a temporary
   file, validate it, atomically admit it, and prune only non-favourites. It
   owns retries, exponential backoff, rate-limit state, and offline operation.
4. **Renderer adapters** ask the catalog for the next eligible local file and
   apply it. The Hyprland adapter can call `awww`; a generic adapter can write
   a selected-path file or execute an explicitly configured local command.

This design makes the project useful even without a GUI. The service can offer
a CLI such as `sources list`, `sources connect smithsonian`, `fetch`,
`review`, `next`, `favourite`, `why-rejected`, and `export`. A GUI can sit on
the same local API later.

## MVP that earns its place

Do not begin with ten providers. Begin with the common catalog, the review
experience, and three adapters that exercise the authentication cases.

| Release | Must include | Reason |
| --- | --- | --- |
| 0.1 | Local-folder importer, NASA SVS, CMA CC0, 4K/orientation/size policy, sidecars, quotas, favourites, source health, CLI, `awww` adapter | This already produces a diverse desktop without an account or unclear rights. |
| 0.2 | Smithsonian API-key connector, system keyring integration, a visual review queue, history, rollback, per-output and ultrawide profiles | This proves credential handling and gives users control over automated choices. |
| 0.3 | Wikimedia public-domain/CC0 adapter, attribution page, duplicate detection, scheduler controls, Waypaper and static-path adapters | This adds breadth only after the provenance model is stable. |
| Later | OAuth only where a provider explicitly supports the use case, GNOME/KDE/macOS/Windows renderer adapters, optional colour-generator hooks | Keep source support dependent on written provider permission. |

Animated content should remain separate in the first releases. The project can
catalogue local MP4, WebM, GIF, and Wallpaper Engine assets and hand them to a
renderer, but it should not scrape live-wallpaper sites or transcode videos in
the background. `mpvpaper` is already a renderer for videos, and
Linux Wallpaper Engine already handles user-owned Steam assets. Source
automation is the more novel and safer problem to solve first.

## Security and privacy requirements

Credential handling cannot be a text box that writes a token into a TOML file.
The connector UI should label the provider, required scope, creation URL,
expiry if known, and exactly what the tool will store. Never send tokens to a
project-operated server. The application should talk directly to the provider.

On a desktop session, use the platform keyring. The freedesktop Secret Service
standard defines a collection and item model for secrets, and Apple documents
Keychain Services as encrypted storage for small secrets. For unattended Linux
services, support a credential file as a deliberate alternative, preferably
systemd encrypted credentials. systemd documents that service credentials are
made available only to the service user and can be encrypted and authenticated
with a local TPM2-derived key. [Secret Service API](https://specifications.freedesktop.org/secret-service/latest/),
[Apple Keychain Services](https://developer.apple.com/documentation/security/keychain-services/),
[systemd credentials](https://systemd.io/CREDENTIALS/)

Practical rules:

* Never put a secret in config exported to Git, Nix store paths, logs, URLs, or
  child-process arguments. Redact request headers in diagnostics.
* Give every adapter an allowlist of HTTPS hosts. Do not follow a redirect to an
  unapproved host. Limit request and image sizes before and after download.
* Decode in a bounded worker and reject malformed files, image bombs, and
  formats the configured renderer cannot handle. Verify image dimensions after
  decoding rather than trusting JSON metadata.
* Use a least-privilege user service. It needs network access only while
  fetching and write access only to its cache and state directories. Renderer
  services get neither network access nor credentials.
* Preserve a signed or immutable metadata sidecar with the source URL, licence
  result, timestamps, checksum, and adapter version. A user should be able to
  inspect or remove a source's whole contribution.
* Make telemetry off by default. There is no product need to report a user's
  wallpaper choices, local file names, monitor layout, or provider account.

## UX and performance details that matter

The UI should lead with a collection view, not a settings form. A thumbnail
shows source, author, licence, resolution, orientation, file size, current
status, and a link back to the original record. Users need actions for preview,
apply now, favourite, block, pause a source, and open attribution. A clear
"why was this skipped?" view will prevent most support questions.

Profiles should be human-sized. "4K landscape" is clearer than a dozen raw
filters. Advanced settings can expose minimum dimensions, aspect-ratio range,
source weights, retention count, and disk cap. Multi-monitor users need both
one image across all outputs and independent output profiles. When a monitor
changes, the catalog should re-evaluate eligibility instead of redownloading.

For performance, discover metadata before downloading originals, fetch slowly
on a timer, use conditional requests where a provider supports them, and never
download during wallpaper rotation. Keep small local thumbnails and create a
perceptual hash after admission so that the same image from two museums does
not consume the cache twice. Decode a full image only on admission or display,
not while scrolling the library. Animated profiles should be opt-in and pause
on lock, battery, and fullscreen use.

## Bottom line

Build it if the goal is a trustworthy personal wallpaper library with several
sources, not a crawler that happens to set a wallpaper. The project is valuable
because it makes provider policy, credentials, quality gates, provenance, and
backend choice concrete in one local tool. Start with a CLI and a Hyprland
adapter, then add a small review UI. If that core is pleasant to use, desktop
backends and carefully approved sources can grow without turning into a brittle
collection of scrapers.
