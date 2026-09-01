# Wallpaper rotation for the Hyprland desktop

## Recommendation

Use a local, curated cache of 4K SDR stills with `awww` as the Hyprland
backend. Rotate locally with a systemd user timer, once per 30 minutes by
default, and download at most one new image per day from each of NASA's
Scientific Visualization Studio and the Cleveland Museum of Art's CC0
collection. Keep the source downloader, cache policy, and wallpaper renderer
separate.

That split is intentional. The renderer should never need network access, and
rotation must keep working while offline. `awww` can replace an image at runtime
with a short transition and works on the wlroots layer-shell protocol used by
Hyprland. It accepts static AVIF and JPEG XL as well as JPEG, PNG, WebP, TIFF,
and other common formats. Its upstream documentation says that time-based
selection belongs in a separate program or script, which makes a systemd timer
a good match. [awww README](https://codeberg.org/LGFae/awww/src/branch/main/README.md)

Do not use `wpaperd` here, even though its feature list sounds close to macOS.
It has directory rotation, output grouping, transitions, and an interval, but
its upstream README explicitly says that Hyprland is unsupported. That is a
bad foundation for a desktop default. [wpaperd README](https://github.com/danyspin97/wpaperd)

The existing Hyprpaper module remains a good static, low-overhead choice for a
fixed image. It is not the right backend for a polished slideshow because it
does not provide a native changing/transition workflow. Use one backend per
session. [Hyprpaper README](https://github.com/hyprwm/hyprpaper)

## What "4K HDR" means in practice

4K and HDR are independent. A 3840x2160 JPEG is normally SDR, and it will look
good on a HDR monitor without being an HDR wallpaper. A complete HDR desktop
also needs a 10-bit output, a monitor HDR mode, and color handling in the
compositor and client.

Hyprland documents `bitdepth = 10` and experimental `cm = "hdr"` monitor
presets. The same page warns that Hyprland color values are not 10-bit and
that some applications cannot screen-capture with 10-bit enabled. This makes
HDR a monitor-profile experiment, not a safe default for an everyday desktop.
[Hyprland monitor documentation](https://wiki.hypr.land/Configuring/Monitors/)

The `awww` daemon documents only 8-bit `wl_shm` pixel formats, `argb`, `abgr`,
`rgb`, and `bgr`. It should therefore be treated as an excellent 4K SDR
wallpaper backend, not a verified HDR renderer, even if the source image is an
EXR or has HDR metadata. [awww daemon manual](https://codeberg.org/LGFae/awww/src/branch/main/doc/awww-daemon.1.scd)

The sensible default is 4K SDR with native-resolution photos. Keep HDR source
files in a separate experimental directory. Only enable the HDR monitor
profile after testing the actual monitor, GPU, compositor, screen sharing, and
the selected wallpaper backend together. Do not silently tone-map or convert a
whole library at login.

## Static image sources

### NASA Scientific Visualization Studio, default automated source

NASA SVS is the best source for the automatic fetcher. Its material is public
domain unless a page says otherwise, it has no API key, it publishes a
documented JSON search and page API, and it commonly publishes new work in 4K.
The page API supplies media URLs, dimensions, filename, credits, and related
metadata. SVS describes newer images and video as usually 4K, publishes stills
as JPEG, PNG, TIFF, and sometimes EXR, and says that public-domain status does
not extend to any licensed music in a visualization.
[SVS API, resolution, and usage documentation](https://svs.gsfc.nasa.gov/help/)

This gives the downloader a clean acceptance rule: query SVS, select a landscape
image that is at least 3840x2160, preserve the page ID, URL, credit, and license
note beside the file, then rotate the local copy. Treat TIFF and EXR as
opt-in candidates. They can be large, and neither Hyprland nor `awww` documents
an end-to-end HDR path for them.

NASA’s general media policy still matters. NASA identifiers may not imply an
endorsement, and a file may contain third-party material called out on its
source page. The downloader should reject anything with a non-public-domain
notice rather than trying to infer rights. [NASA image and media guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/)

### NASA Image and Video Library, secondary automated source

NASA’s Image and Video Library is a useful source of mission photography. Its
unauthenticated API has a `media_type=image` search and asset manifest endpoint
that exposes original downloadable assets and metadata. It does not promise
4K, so apply the same dimension filter before admitting a file to the cache.
[NASA Image and Video Library API](https://images.nasa.gov/docs/images.nasa.gov_api_docs.pdf)

### Cleveland Museum of Art Open Access, recommended non-space automated source

The Cleveland Museum of Art (CMA) is the strongest complementary automatic
source. It provides a public API with no key or token, a `cc0` filter, image
links that carry dimensions and file sizes, and separate web, print, and
original image variants. Only records whose `share_license_status` is `CC0`
expose CC0 images; the fetcher must enforce that field rather than treating
all collection metadata as permission to download. The collection covers art,
design, landscapes, architecture, Asian art, and historical photography, so it
adds visual variety without turning a background service into a general image
scraper. [CMA Open Access API](https://openaccess-api.clevelandart.org/)

For a 4K desktop, select a landscape `original` only after decoding it and
verifying at least 3840x2160 pixels. CMA documents the print derivative as
3400px on its long side, so it is not sufficient for a strict 4K requirement;
the original TIFF is variable-sized and should remain subject to the existing
byte cap. Download at most one item per scheduled run, retain the API record
and CC0 status in the sidecar, and fall back to the current wallpaper when no
eligible landscape is returned. The API is keyless, so it has a lower privacy
and secret-management cost than commercial stock-photo APIs. [CMA API image
specifications and licence field](https://openaccess-api.clevelandart.org/)

### Smithsonian Open Access, optional API-key source

Smithsonian Open Access is a strong opt-in source for public-domain fine art,
natural history, design, and historical photography. Assets explicitly marked
CC0 may be used, transformed, and shared without permission; the catalog
includes JPG and, where available, TIFF. Its public API requires an API key,
so it must be stored outside the Nix store (for example, a credential file read
only by the fetch service), never in a generated Nix configuration. Accept
only records whose *media asset* is identified as CC0, not merely records with
CC0 metadata, and apply the same decoded 4K-landscape test. [Smithsonian Open
Access FAQ](https://www.si.edu/openaccess/faq)

This is intentionally optional rather than a default source: it adds a
credential and an external account relationship, while many collection records
do not have a media file or a 4K-capable landscape derivative. A once-daily
single-query fetch is comfortably within the API-management service's public
limits; a real key is preferable to `DEMO_KEY`, whose documented limits are 30
requests per IP per hour and 50 per day. [api.data.gov developer
manual](https://api.data.gov/docs/developer-manual/)

### USGS and NOAA, curated nature and Earth-photography pools

The USGS Multimedia Gallery is a valuable manual-curation pool for landscapes,
geology, water, weather, and wildlife. USGS says its gallery items are public
domain unless otherwise noted. The source does not provide the same
purpose-built, stable wallpaper-search contract as CMA, so it should feed a
reviewed local collection rather than a random automatic downloader. Preserve
the item's credit and only admit images that pass the resolution and landscape
tests. [USGS Multimedia Gallery](https://www.usgs.gov/products/multimedia-gallery/overview)

NOAA is similarly useful for ocean, coast, atmosphere, and wildlife imagery,
but it must remain a curated source. NOAA-created media is generally not
copyrighted, while third-party material can appear on its sites and is marked
with a copyright holder. For automatic operation that distinction is too easy
to get wrong; use only files whose source metadata expressly identifies NOAA
as creator, retain the credit, and do not use names or marks in a way that
implies endorsement. [NOAA image licensing and usage
information](https://www.omao.noaa.gov/image-licensing-usage-info)

## Recommended source tiers

| Tier | Source | Content | Automation decision |
| --- | --- | --- | --- |
| Default automatic | NASA SVS | Science and space visualizations | Enabled, public-domain check plus 4K validation |
| Default automatic | Cleveland Museum of Art Open Access | Fine art, design, history, landscapes | Enable as a separate CC0-only feed; no key; original-image and 4K validation |
| Opt-in automatic | Smithsonian Open Access | Fine art, natural history, design, historical photography | Require a user-managed API-key credential; CC0-media-only and 4K validation |
| Manual/curated | USGS Multimedia Gallery | Landscapes, geology, water, weather, wildlife | Download through the chooser/import action after review |
| Manual/curated | NOAA | Ocean, coast, atmosphere, wildlife | Import only explicitly NOAA-created/public-domain assets after review |
| Manual/curated | Wikimedia Commons | Photography, art, landscapes, architecture, history | Inspect and import public-domain/CC0 files only; retain licence and creator information |
| Manual only | Wallhaven | Community-uploaded art and photography | Import only after verifying the original creator's rights; never an automatic feed |

The usable collection is therefore not limited to space: the two automated
defaults deliberately mix scientific imagery with open-licensed art, and the
optional/manual tiers add natural history, landscapes, architecture, ocean,
weather, and historical photography. Rotation itself remains local and source
agnostic; every admitted file is still subject to the same size, image-decoder,
dimension, provenance, cache, and sandbox rules.

### Wikimedia Commons, manual PD/CC0 source

Wikimedia Commons is the broadest complementary source for a licence-aware
automatic cache: photography, art, landscapes, architecture, and historical
images are all represented. Its stable `imageinfo` API returns the original
file URL, dimensions, MIME type, and extended metadata. The fetcher may admit
only files explicitly identified as public domain or CC0, retain the author,
source URL, and licence in its sidecar, and reject every other licence by
default. That avoids trying to satisfy per-file attribution and share-alike
requirements in a lock-screen/background workflow. [MediaWiki Imageinfo
API](https://www.mediawiki.org/wiki/API:Imageinfo/en) and [Commons reuse
guidance](https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia/en)

The module deliberately does not include Commons in its automatic-source list:
all media are not equally licensed and a random feed is not a quality guarantee.
A user may manually add a reviewed local image with `desktop-wallpaper-add`.
If a future opt-in collector is added, it must use a descriptive, contactable
User-Agent, cache API results, request serially or in small batches,
set `maxlag` for non-interactive requests, and obey retry/backoff behaviour.
[MediaWiki API
etiquette](https://www.mediawiki.org/wiki/API:Etiquette/en) and [Wikimedia API
usage guidelines](https://foundation.wikimedia.org/wiki/Policy:Wikimedia_Foundation_API_Usage_Guidelines)

### Sources not suitable for the automated module

Unsplash’s API terms require hotlinking and a download event for a wallpaper
action, and its API guidelines prohibit wallpaper applications. That conflicts
with a local rotating cache, so do not use its API in the module. Do not embed
an Unsplash API key in the desktop configuration. [Unsplash API
guidelines](https://help.unsplash.com/en/articles/2511245-unsplash-api-guidelines)
and [API terms](https://unsplash.com/api-terms)

Pexels’ API documentation explicitly forbids making Pexels content available
as a wallpaper app. Exclude it from both the module and its optional sources.
[Pexels API documentation](https://www.pexels.com/api/documentation/)

The Art Institute of Chicago is excellent for manually chosen public-domain
art, but not for the 4K automatic path. Its own API documentation asks clients
to use its 843px common derivative (or 1686px where a larger public-domain
image is appropriate), warns that IIIF results can include non-public-domain
works, and requests single-threaded scraping at no more than one request per
second. That is an unsuitable combination for an unattended 4K wallpaper
feed. [Art Institute of Chicago API documentation](https://api.artic.edu/docs/)

Wallhaven has a documented API with resolution, category, purity, tag blacklist,
and collection controls, but it hosts user-uploaded work with no reliable,
machine-readable reuse licence. Its own FAQ also asks users not to run scraper
or mass-download scripts. Do not implement it as an automatic source, even for
SFW results. A user can manually import a specific item only after verifying
the original creator's permission, just as they would for any personal image.
[Wallhaven API](https://wallhaven.cc/help/api), [Wallhaven
FAQ](https://wallhaven.cc/faq), and [Wallhaven rules](https://wallhaven.cc/rules)

Bing's familiar daily-image endpoint is not a supported wallpaper-content API
with a documented reuse licence. Microsoft retired the Bing Search APIs in
2025, and its announced replacement is grounding for agents rather than image
delivery. Do not depend on undocumented image-archive endpoints for a desktop
cache. [Microsoft Bing Search API retirement
notice](https://learn.microsoft.com/en-us/lifecycle/announcements/bing-search-api-retirement)

## UX and module shape

The default module should offer a static rotation mode, an animated mode, and
a "fixed" fallback. They are mutually exclusive because two layer-shell
wallpaper backends will fight for the same background surface.

| Mode | Backend | Default UX | Cost |
| --- | --- | --- | --- |
| Fixed | Hyprpaper | Current explicit per-output image mapping | Lowest steady-state overhead, no slideshow |
| Rotating stills | `awww` plus local picker/timer | Short fade, next/previous/favourite actions, persisted current choice | One image decode and transition per change; no network during rotation |
| Animated image | `awww` GIF | Explicit opt-in for a small, pre-sized loop | Initial frame caching can use substantial CPU and memory |
| Video | mpvpaper | Explicit opt-in and visibly labelled as power-hungry | Continuous decode and rendering; use only with a short, local, muted loop |

Waypaper is a useful optional visual chooser. Its upstream project supports
`awww`, Hyprpaper, and mpvpaper; its `waypaperd` slideshow changes an image
periodically and it can restore the selected wallpaper at startup. It is a UI,
not the source-of-truth scheduler. The Home Manager module should expose it as
a launcher action rather than require it for normal rotation. [Waypaper README](https://github.com/anufrievroman/waypaper)

For the macOS-like experience, add these user-visible actions:

* Open wallpaper picker.
* Next and previous image.
* Pause or resume rotation.
* Keep the current image as a favourite.
* Reveal the source and attribution metadata.
* Switch to the fixed fallback if the backend fails.

An interval of 30 minutes is a good default. It is long enough to make the
transition feel deliberate and avoids pointless image decoding. A user service
should set the first wallpaper at graphical-session startup. A persistent
systemd timer can run the local "next" command after that, so missed intervals
are handled after sleep or reboot without a long-running selection daemon.

## Safe automatic fetch design

The downloader is the only component allowed to access the network. It should
be a low-frequency, hardened user service, separate from `awww` and the timer.

1. Allow only HTTPS and the NASA SVS or NASA Image Library hosts. Do not accept
   a URL from title, description, or arbitrary page metadata.
2. Fetch JSON and media into a private temporary directory. Never interpolate
   remote values into a shell command.
3. Apply a byte limit before downloading. Check HTTP success, the content type,
   an image signature, decoder readability, landscape aspect ratio, and at
   least 3840x2160 dimensions.
4. Store a small sidecar JSON record containing source URL, source ID, title,
   credit, licence note, dimensions, checksum, and retrieval date. Atomically
   rename only a fully validated file into the cache.
5. Bound the cache by both count and total bytes. Prune only images that are not
   current or favourited. Keep the last known-good file if every fetch fails.
6. Make network fetches infrequent, for example daily, and rotate only local
   files. This gives predictable performance, works offline, and limits data
   sent to a content provider.
7. Run the fetch service with a private temporary directory, a read-write path
   limited to the wallpaper cache, no privilege escalation, no access to home
   secrets, a timeout, and a restricted address family. The exact systemd
   sandbox settings need testing against `curl` and the chosen image inspector.

Downloading and decoding image files are untrusted-input operations. Keep the
fetcher separate from the compositor. A malformed file should fail validation
and leave the old wallpaper in place, never crash or restart the wallpaper
renderer.

## Animated and video alternatives

`awww` is the right low-cost animated option for a compact GIF. It supports
animated GIFs and compresses cached frames. Its own troubleshooting section
warns that caching a large GIF, especially one that requires resizing, takes
noticeable CPU. Pre-size a loop to the output resolution, cap it at a modest
frame rate, and do not use it on battery by default.
[awww README](https://codeberg.org/LGFae/awww/src/branch/main/README.md)

For video, mpvpaper is the practical wlroots backend. It runs mpv on a chosen
output or all outputs and can forward a deliberately restricted set of mpv
options. It should use a local, muted, short loop. Do not pass a remote playlist
URL, do not enable audio, do not load a normal interactive mpv configuration,
and gate startup on AC power or an explicit user choice. mpvpaper does not make
a claim that it preserves HDR to a HDR Hyprland output, so treat 4K HDR video
wallpaper as experimental.
[mpvpaper README](https://github.com/GhostNaN/mpvpaper)

Steam Wallpaper Engine content has third-party licensing, proprietary delivery,
and compatibility gaps in Linux reimplementations. It does not belong in the
baseline. If a user explicitly wants it, place it behind a separate optional
module and fall back to a still image when playback fails.

## Integration checks before enabling by default

Test these on the physical desktop after activation:

1. A 4K SDR image appears at native size on every configured output and remains
   correct through dock, unplug, lock, sleep, and resume.
2. The timer changes only the `awww` wallpaper and never starts Hyprpaper.
3. The picker, next, previous, pause, and favourite actions work without
   requiring network access.
4. A source fetch with a corrupted, oversized, portrait, unsupported, or
   third-party-marked image leaves the last wallpaper in place and records a
   useful log message.
5. CPU, memory, GPU use, and wakeups remain idle between static changes. Test
   an animated GIF and video loop separately on AC and battery.
6. If HDR is enabled, test ten-bit output, color appearance, lock screen,
   screenshot, portal screen sharing, and ordinary applications. Disable HDR
   if any of those regressions are unacceptable.
