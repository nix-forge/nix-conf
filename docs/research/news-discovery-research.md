# Curated news discovery and reading

> Historical snapshot: personal package recipes referenced here have since been retired or renamed. These audit findings describe the cited source, not the current package selection.

Reviewed: 2026-10-03. Scope: personal, self-hosted news reading on the NixOS homelab. The original Miniflux trial and the visual-reader follow-up are summarized below; source quality remains an editorial choice.

## Current reader decision

Use **ReactFlux as the new visual interface over the existing Miniflux engine**. This provides the largest practical interface improvement with a small native deployment: static assets served by the existing proxy, Go fetching and extraction, and PostgreSQL already present. FreshRSS is now disabled in host configuration; its data remains on disk under the host backup selection. FreshRSS retirement and the article-quality upgrade are active. The implementation and its validation are recorded below.

PHP itself is actively maintained: PHP 8.5 has active support through December 2027 and security support through December 2029. Backend language age does not determine interface quality. Nevertheless, Miniflux plus ReactFlux satisfies the preference for a contemporary frontend and a non-PHP primary reader. [PHP supported versions](https://www.php.net/supported-versions.php).

## Content and image quality review, October 2026

The following findings use public feeds, current Miniflux documentation, and the pinned ReactFlux revision. They establish concrete acquisition and rendering limitations, but do not prove which limitation affected a particular stored story. Prefer the publisher's own photographs, figures, and captions; stock or generated images would misrepresent the reporting.

### The feed is often only a teaser

A direct HTTPS sample of the first three entries of each public feed produced the following approximate word counts. The script selected `content:encoded` when present, otherwise `description`, stripped HTML, and counted whitespace-separated tokens. Counts are a diagnostic, not a quality score or proof of completeness.

| Publisher feed | Body word count range | Inline image count range | Practical treatment |
| --- | --- | --- | --- |
| [Science News](https://www.sciencenews.org/feed) | 18 to 21 | 0 | Test full-article extraction. |
| [Quanta](https://www.quantamagazine.org/feed/) | 65 to 73 | 0 | Test full-article extraction. |
| [BBC World](https://feeds.bbci.co.uk/news/world/rss.xml) | 19 to 21 | 0 | Headlines plus tested extraction. |
| [Guardian World](https://www.theguardian.com/world/rss) | 92 to 155 | 0 | Test extraction; retain publisher image variants. |
| [PBS NewsHour](https://www.pbs.org/newshour/feeds/rss/headlines) | 26 to 47 | 0 | Test extraction, including video-only exceptions. |
| [Ars Technica](https://feeds.arstechnica.com/arstechnica/index) | 111 to 178 | 0 | Public summaries or an authorized subscriber feed. |
| [ProPublica](https://www.propublica.org/feeds/propublica/main) | 176 to 3018 | 1 to 11 | Prefer supplied content; some entries are shorter formats. |
| [The Markup](https://themarkup.org/feeds/rss.xml) | 935 to 3013 | 2 to 13 | Prefer supplied content. |

The first BBC entry supplied a 240-by-135 thumbnail outside its body. The first Guardian entry supplied three renditions of the same image at widths 140, 460, and 700, with different signed URLs. Quanta supplied a separate WebP image with an `image/jpg` MIME label. These are observed examples, not assumptions about every item. Enlarging a 240-pixel thumbnail into a large card can explain visible blur. Editing a signed URL can break it.

The [Ars feed directory](https://arstechnica.com/rss-feeds/) explicitly directs subscribers to personalized full-text feeds. If using that option, keep the private feed URL out of public Nix source. [Guardian's guide](https://www.theguardian.com/help/feeds) documents section RSS and personal, noncommercial use under its terms.

### Miniflux acquisition and image handling

Miniflux's per-feed "Fetch original content" setting downloads articles automatically. The article view also has a manual fetch action. Without custom selectors, extraction uses Readability. This consumes additional requests and resources. [Miniflux UI documentation](https://miniflux.app/docs/ui.html).

The API exposes `crawler`, `scraper_rules`, and `rewrite_rules` on feeds, supports updating existing feeds, and has an endpoint to fetch an existing article's original content. A first-run import alone does not update existing subscriptions or repair old entries. [Miniflux API](https://miniflux.app/docs/api.html).

Start with `crawler=true` on a small tested set. Use custom CSS selectors only when the built-in extraction fails. `add_dynamic_image` attempts to recover high-quality lazy or responsive images. `use_noscript_figure_images` can recover fallback figures. `remove_img_blur_params` exists, but changing image URL parameters needs publisher-specific testing. `add_enclosure_links` adds links, not editorial placement of figures in prose. These rewrite rules are comma-separated. [Miniflux rules](https://miniflux.app/docs/rules.html).

`MEDIA_PROXY_MODE=all` proxies HTTP and HTTPS resources; the default resource type is image. This is transport behavior, not image enhancement. Keep fetching private networks disabled, bounded polling, and the existing per-host request limit. [Configuration reference](https://miniflux.app/docs/configuration.html).

### ReactFlux has separate article and attachment paths

The pinned [entry presentation code](https://github.com/electh/ReactFlux/blob/7151bbb61185ca219f4c141cb9cdd5e64a48134e/src/utils/entry-presentation.js) selects the first inline `img.src`, then a video poster, then the first image attachment for its card cover. It does not consider `srcset` for this choice. The image-extension fallback recognizes GIF, JPEG, and PNG. An enclosure with no useful image MIME type and only a WebP or AVIF extension can therefore be classified as a file.

The existing local `chooseCoverImage` patch improves only the attachment fallback. It compares URLs with the same origin and pathname, reads a `width` query parameter, and caps candidates at 1024. It cannot improve the preferred inline image, a size embedded in a URL pathname, or a size hidden inside a proxied URL. This is a narrow remedy, not a general image-quality policy.

[ArticleEnclosures](https://github.com/electh/ReactFlux/blob/7151bbb61185ca219f4c141cb9cdd5e64a48134e/src/components/Article/ArticleEnclosures.jsx) deliberately renders attachments as a separate disclosure with image previews. [ArticleDetail](https://github.com/electh/ReactFlux/blob/7151bbb61185ca219f4c141cb9cdd5e64a48134e/src/components/Article/ArticleDetail.jsx) places that disclosure after the parsed article HTML and starts it closed. Thus a feed image enclosure is not an inline editorial figure. Recovering the publisher's actual article HTML is the preferable fix.

If blur remains after extraction, compare each affected image's downloaded dimensions with rendered CSS width and device pixel ratio. Choose a larger publisher-supplied rendition of the same picture and preserve signed URLs. Avoid upscaling a thumbnail to fill a banner. Any renderer patch should have a concrete failing example, including duplicate image handling and malformed MIME metadata.

### Source selection and the simpler interface

Use Science News and Quanta for specialist science reporting, supported by their [editorial descriptions](https://www.sciencenews.org/about-science-news) and [Quanta mission](https://www.quantamagazine.org/about/). Keep ProPublica for investigations and The Markup for reporting about technology's effects. ProPublica publishes [source-verification and correction standards](https://www.propublica.org/code-of-ethics); The Markup describes its [investigative focus](https://themarkup.org/about). These are editorial reasons to sample them, not guarantees about every article.

Use a small broad-reporting group rather than overwhelming the queue with every available feed. Keep institutional science announcements in a separate primary-source category. Avoid duplicating Ars general and Ars science unless both are wanted. Do not remove valuable short reporting merely to optimize word count. Review duplicates, opinion, sponsored material, extraction errors, and actual reading value before expanding the roster.

Native Miniflux supports responsive reading, light/dark and serif/sans-serif themes, and custom CSS and JavaScript. A small stylesheet can improve measure, line height, spacing, image maximum width, caption contrast, and touch targets. This is a viable lower-maintenance fallback, but CSS cannot supply missing photographs or paragraphs. [Miniflux features](https://miniflux.app/features.html). Prefer a small stylesheet over a third frontend or a large JavaScript theme.

### Validation and limits, October review

Public-feed retrieval and pinned upstream source inspection ran on Linux without a system build or service activation. Public source sampling made no authenticated requests. No live database, account crawler settings, existing article contents, rendered image dimensions, or mobile Safari behavior were inspected. The NASA feed request failed DNS resolution. A repeat Science News request without the initial browser-like user agent failed HTTP, so fetching can depend on the requester. No full-article extraction test ran in this research assignment.

Before calling the stack repaired, compare several stories per selected feed against their publisher pages. Check complete paragraphs, captions, figures, image resolution, source links, paywall or consent responses, and narrow-screen rendering. Test both newly fetched and existing unread entries. A successful feed refresh alone proves none of these.

### Implemented configuration and reader changes

The [host news module](../../hosts/nixos/desktop/local/homelab/news.nix) now owns a
twelve-feed roster. It enables crawling for Science News, BBC World, Quanta,
Ars Technica, PBS NewsHour, Guardian World and Guardian Technology. Temporary
live probes compared three articles per source before selecting rules. BBC's
`article` selector recovered bodies and images that the existing built-in rule
missed. Science News uses `article > header figure, article .rich-text`; this
excludes its author biography and related-story image list. Quanta uses
`.post > div > figure, .post__content.wysiwyg` to preserve article figures and
avoid selecting nested content twice. These selectors reflect observed publisher
HTML and need review when those sites change.

ProPublica, The Markup, The Conversation and MIT Technology Review retain supplied
feed content. ESA stays uncrawled because its feed mixes image briefs and articles,
and sampled extraction lost an existing image or returned empty content. New
accounts put ESA in a primary-source category. NYT Science and the duplicate
Ars Science subscription are disabled in the existing account, preserving their
articles and saved state. They are omitted from new-account seeds.

The reusable [Miniflux module](../../nix-homelab/modules/optional/miniflux.nix) accepts
per-feed extraction settings and an opt-in, versioned `contentUpgrade`. Bootstrap
imports subscriptions without synchronously crawling the entire archive and
journals incomplete feed configuration. The upgrade updates existing matched
subscriptions once, preserves custom rules and CSS, and repairs at most thirty
recent unread items per enabled feed in this deployment. It fetches candidate
content without persistence before replacing a short excerpt. Failed requests
retry up to three times; progress and aggregate results remain in private state.
It never writes read/star state or article titles. Subsequent starts leave user
changes alone. [Module setup](../../nix-homelab/docs/optional-services.md#miniflux).

The API returns display HTML with signed proxy URLs. Before PUT, the helper
restores original publisher URLs belonging to the configured built-in proxy and
escapes attribute-sensitive characters. Otherwise the next API read would proxy
the stored proxy URL again. Custom media proxies are rejected for this optional
upgrade. [Miniflux 2.3.3 API implementation](https://github.com/miniflux/v2/blob/2.3.3/internal/api/entry_handlers.go),
[proxy rewriting](https://github.com/miniflux/v2/blob/2.3.3/internal/mediaproxy/rewriter.go).

The [ReactFlux package](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/re/reactflux/README.md) now selects
responsive publisher image renditions, recognizes WebP and AVIF enclosures,
and reads dimension metadata through standard Miniflux proxy URLs without
altering the URLs it requests. Image enclosures appear as visible figures after
the article; ordinary files remain collapsible. The existing gallery deduplicates
inline images and responsive variants, preserves captions, and opens a sharper
lightbox rendition. Grid covers scale down small images instead of stretching
them. No stock images, URL-size guesses or new runtime dependencies were added.

The [native stylesheet](../../hosts/nixos/desktop/local/homelab/miniflux-reader.css)
uses readable article measure, serif body text, responsive figures, captions,
and visible keyboard focus while retaining the selected Miniflux theme.
It installs through the account's API `stylesheet` field only when empty.
There is no `CUSTOM_CSS` environment variable or required image-display toggle.

FreshRSS host selection, dashboard entry, HTTPS route and service-specific secret
restart declarations were removed. Its database remains on disk under the host's
existing `/var/lib` backup selection. Reusable FreshRSS packages and modules remain
available. The live Miniflux database was backed up before mutation; a backup
restore drill was not part of this change.

### Implementation validation

Eight Python behavioral tests cover recovery after interrupted feed creation,
bounded retries, preservation of custom settings, completed-revision behavior,
and publisher-URL restoration. The native NixOS VM test checks real Miniflux and
PostgreSQL, initial extraction, repaired content and captions, preserved read/star
state, successful image-proxy HTTP retrieval, original URLs in storage, and
user changes surviving restart. The ReactFlux package passes seven existing
authentication/media tests and five new image tests against its actual entry,
gallery and component code. Baseline image tests failed before the patch.

The desktop system build passed. Two completed migration revisions repaired 163 excerpts with zero failed fetches.
The second revision corrected the stored Guardian Technology subscription URL. Stored article HTML contained
no nested proxy URLs. The repository-wide package check stopped at an existing
cross-platform overlay/package-metadata contract mismatch outside this change;
Focused package and Miniflux tests passed. Authenticated ReactFlux browser
checks confirmed loaded card images, extracted article figures and captions,
visible PBS image enclosures, and a 390-pixel layout without horizontal overflow
or JavaScript errors. Native Miniflux also applied the serif stylesheet and
kept article images within the same phone viewport. These checks used Chromium,
not physical-device Safari. Historical September checks are not evidence for this patch.

## Earlier comparison and deployment history

The remaining sections record September trials and validation. Their references to a running FreshRSS archive describe the earlier deployment, not the newly selected configuration.

### Comparison

| Candidate | Current maintenance evidence | UI and deployment fit | Limit |
| --- | --- | --- | --- |
| ReactFlux + Miniflux | MIT, commit `7151bbb61185ca219f4c141cb9cdd5e64a48134e`, September 25 | Modern static frontend; image cards, column and list views, touch navigation; retains native Miniflux capabilities | Browser credential persistence needs hardening; PWA is not proof of offline articles |
| FriRSS + FreshRSS | MIT, v1.4.12, September 25 | Three panes, themes, Readability, labels, offline images; preserves FreshRSS data | Adds Express/SQLite runtime; browser-side history search; young project |
| Fusion | MIT, v1.2.1, July 28 | React frontend with Go/SQLite single executable, responsive PWA, Fever API | Simpler workflows; no documented equivalent to rich filtering/labels/extraction |
| CommaFeed | Apache-2.0, 7.3.2, August 22 | React/Quarkus, several layouts, mobile support, native executable available | Requires a new engine and state migration; no demonstrated advantage for this installation |
| Nextflux | Last observed commit May 20; no release and no LICENSE file found | Attractive static Miniflux client | README explicitly recommends a native client on mobile; ambiguous licensing excludes packaging |
| Feedbin | Maintained Rails repository | Polished web product and client API | Maintainer explicitly discourages production self-hosting without substantial operational time |
| Folo | Desktop v1.14.0, September 18 | Polished cross-platform service frontend | Public client and SSR code do not establish an available self-hosted fetching/authentication backend |

Release information was checked using the projects' GitHub release APIs rather than search-result snippets, which lagged several versions. [ReactFlux revision](https://github.com/electh/ReactFlux/tree/7151bbb61185ca219f4c141cb9cdd5e64a48134e), [FriRSS release](https://github.com/Fripix/Frirss/releases/tag/v1.4.12), [Fusion release](https://github.com/0x2E/fusion/releases/tag/v1.2.1), [CommaFeed release](https://github.com/Athou/commafeed/releases/tag/7.3.2), [Nextflux](https://github.com/electh/nextflux), [Feedbin](https://github.com/feedbin/feedbin), [Folo releases](https://github.com/RSSNext/Folo/releases).

## ReactFlux findings

The pinned README documents card/list/column layouts with configurable covers and summaries, image galleries, attachments, reading fonts and widths, publication-date filters, native Miniflux full-text search and extraction, duplicate suppression, batch feed operations, third-party saving, and touch gestures. These match the visual browsing requirement substantially better than another FreshRSS stylesheet. Miniflux 2.3.2 or newer is required. [Pinned README](https://github.com/electh/ReactFlux/blob/7151bbb61185ca219f4c141cb9cdd5e64a48134e/README.md).

Its package manifest uses React 19.3, Vite 8, pnpm 11.21, virtualization and lazy loading libraries. It builds static files; Node is needed during compilation, not as an application server. Pin the source and lockfile in the personal package repository, use the available Nix package machinery, and serve the compiled result through the existing native proxy. [Package manifest](https://github.com/electh/ReactFlux/blob/7151bbb61185ca219f4c141cb9cdd5e64a48134e/package.json).

Source observations requiring deployment work:

- `authState` persists credentials through `persistentAtom`, including the supplied password or API token. Prefer a dedicated revocable token, or a same-origin bridge issuing an HttpOnly session. Never compile shared credentials into static assets. [Authentication store](https://github.com/electh/ReactFlux/blob/7151bbb61185ca219f4c141cb9cdd5e64a48134e/src/store/authState.js).
- The login page accepts `server`, `token`, `username`, and `password` query parameters. It removes them on form submit, after the initial request already reached the server. Remove credential query prefill for this deployment. Native fetch already uses `redirect: error`, a useful defense against redirect credential forwarding. [Login implementation](https://github.com/electh/ReactFlux/blob/7151bbb61185ca219f4c141cb9cdd5e64a48134e/src/pages/Login.jsx).
- Article HTML is parsed into React elements rather than independently sanitized. It relies on Miniflux's sanitized content. Test malicious feed fixtures and set a restrictive CSP; assess permitted media/embed origins rather than allowing arbitrary frames. [Article renderer](https://github.com/electh/ReactFlux/blob/7151bbb61185ca219f4c141cb9cdd5e64a48134e/src/components/Article/ArticleDetail.jsx).
- Covers come from the first content image, video poster or image enclosure. Empty feeds cannot reliably produce publisher imagery. Use a neutral fallback and prefer feeds containing proper media metadata; avoid fetching every story's page just for a thumbnail. [Entry presentation](https://github.com/electh/ReactFlux/blob/7151bbb61185ca219f4c141cb9cdd5e64a48134e/src/utils/entry-presentation.js).
- The service worker caches the shell, build assets and fonts. No article API/image offline caching policy was found in the inspected configuration. Describe the result as an installable PWA, not verified offline reading. [Vite/PWA configuration](https://github.com/electh/ReactFlux/blob/7151bbb61185ca219f4c141cb9cdd5e64a48134e/vite.config.js).

## Why other choices ranked lower

FriRSS is a meaningful alternative, particularly if preserving FreshRSS labels and richer offline reading are priorities. Its maintainer documents offline preparation including images, typography/themes, gestures, extraction and an SSRF-guarded proxy. The project also explicitly says it was largely built through AI-assisted iteration; that is reason to inspect behavior, not an automatic rejection. Search scans articles in the browser because the Google Reader API lacks search. [FriRSS README](https://github.com/Fripix/Frirss/blob/v1.4.12/README.md). Its production build contains compiled Node ESM, static Vite assets and better-sqlite3, so a native Nix package is possible without Docker. [Build recipe](https://github.com/Fripix/Frirss/blob/v1.4.12/Dockerfile).

Fusion's frontend has React 19, TanStack Query/Router, shadcn and URL-based article state. The Go backend uses SQLite FTS5, conditional requests, bounded polling, backoff and private-network blocking. These are good structural choices. The documented model is feeds/groups/articles/bookmarks; the inspected docs did not show full-text article extraction, labels or sophisticated content rules. It would exchange existing capabilities for a smaller stack. [Frontend design](https://github.com/0x2E/fusion/blob/v1.2.1/docs/frontend-design.md), [Backend design](https://github.com/0x2E/fusion/blob/v1.2.1/docs/backend-design.md).

CommaFeed is a credible maintained alternative with React, native Quarkus compilation, responsive layouts, Fever API and automated read rules. Version 7.3.2 fixes cross-user starring/tagging authorization, so older versions should not be selected. The package and runtime are feasible, but replacing the engine offers little advantage over an improved Miniflux frontend here. [CommaFeed README](https://github.com/Athou/commafeed), [Security-fix release](https://github.com/Athou/commafeed/releases/tag/7.3.2).

Feedbin's own README warns that self-hosting is at odds with its hosted-product goal and requires significant configuration. Its optional extraction/image services would add operational work. [Feedbin README](https://github.com/feedbin/feedbin).

Folo's public README links browser/mobile/desktop clients, not a supported complete self-host deployment. Inspection of the current tree found client, SSR, landing and update applications, with no matching fetch/auth backend. This is a limited observation, not proof that a future release cannot support self-hosting. Do not select it based on third-party directories calling it self-hosted. [Folo repository](https://github.com/RSSNext/Folo).

FreshRSS users improve the default interface through Custom CSS, themes, Grid View/other extensions, and API clients. The official docs say custom themes can be overwritten on update. A maintained separate frontend is a stronger answer to a requirement for a substantially different interface than another incremental CSS patch. [FreshRSS themes](https://freshrss.github.io/FreshRSS/en/admins/11_Themes.html), [Official extension collection](https://github.com/FreshRSS/Extensions), [Client compatibility matrix](https://github.com/FreshRSS/FreshRSS).

## Deployment and verification

The selected deployment packages ReactFlux from the pinned upstream source in the personal package repository. The native homelab module serves static files through nginx and proxies only the existing loopback Miniflux API, media and feed icons. Node is a build dependency; there is no new Node service or container. FreshRSS remains available as an archive.

Reader defaults select image cards, short summaries, reading time, system theme, descending publication dates and URL duplicate suppression. Opening a card reads it inside the reader; scrolling does not automatically mark articles read. Existing browser preferences take precedence over defaults.

Local adaptations remove credential-bearing query parameters and durable password storage. Password sign-in exchanges the password for a Miniflux API key; the browser retains only the key in tab session storage. Closing the session requires sign-in again. Logging out clears the browser session but does not revoke a key shared by the deployment. Revocation remains available in Miniflux. External favicon lookup is disabled, updates are managed by Nix, and non-native external HLS video has a media-player link fallback. Image cards prefer a publisher-supplied larger rendition of the same image, capped at 1,024 pixels, instead of a small thumbnail. The implementation preserves signed URLs and does not request an invented image address.

The service worker supports an installable application shell. Offline article reading is not implemented. On iPhone, start with the HTTPS reader URL in Safari and optionally add it to the Home Screen. A native client using Miniflux remains an alternative; clients synchronize through the backend rather than the ReactFlux interface.

The migration preserves both databases and takes a root-only backup before updates. It imports missing subscriptions and unions matching read/star states without deleting entries. Older articles unavailable in Miniflux remain in the FreshRSS archive.

### Verified behavior

The personal package policy check and seven behavioral authentication/session/media tests passed. A native NixOS VM test passed against the real Miniflux and PostgreSQL services, including rejected anonymous/incorrect logins, API key creation/use/revocation, loopback bindings, SPA and cache headers, real feed icons, unsafe article HTML removal and nginx restart persistence. The Bitwarden importer alias regression suite passed 21 tests.

Live browser checks verified image cards and feed icons, descending publication dates, in-reader articles, bookmarks across reload, text search, publication-day filtering, preferences and mobile category navigation. A 390 by 844 viewport loaded images without horizontal document overflow. Test read/bookmark changes were restored. These are browser viewport checks, not a physical iPhone Safari/PWA test.

The native frontend uses the existing nginx process and adds no application daemon. A live Miniflux service measurement was about 45 MiB; this excludes PostgreSQL, shared nginx and client-browser memory and is not a workload benchmark. The configured public hostname retains the existing LAN/VPN access restrictions.

## Earlier FreshRSS visual trial

The first Miniflux trial did not meet the request for an image-led browsing interface. Its [documented web views](https://miniflux.app/docs/ui.html) favor a list and an article view. The earlier configuration trial selected **FreshRSS 1.30.0 with the official Grid View extension** alongside Miniflux. Grid View provides responsive cards with feed thumbnails, content-image fallback, and a text placeholder when no image exists. It preserves the choice to switch back to the standard view. The extension's optional article-page Open Graph fetching remains off: the implementation can fetch a URL supplied by a logged-in user and does not enforce the homelab's private-address policy. [Official extension and README](https://github.com/FreshRSS/Extensions/tree/main/xExtension-GridView), [FreshRSS 1.30.0 release](https://github.com/FreshRSS/FreshRSS/releases/tag/1.30.0).

FreshRSS adds saved queries, labels, search, OPML portability, and a mobile-friendly browser interface. Its Google Reader API also supports native iPhone clients, although each user must enable API access and set a separate API password. The HTTPS URL is the simplest first iPhone route; the free, open-source [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire) is a reasonable client to test once API access is configured. Miniflux remains available with its existing read state, passkeys and integration path. A second reader creates two independent read-state databases; use one as the daily reader after the trial. [FreshRSS mobile and API guide](https://freshrss.github.io/FreshRSS/en/users/06_Mobile_access.html), [Miniflux Google Reader integration](https://miniflux.app/docs/google_reader.html).

The current starter roster is fourteen publisher-owned feeds across broad reporting, investigations, science, technology, and discovery. Live XML checks found image metadata in sampled PBS, Guardian, Ars and Quanta items, and an embedded image in a sampled CalMatters item. Some entries will still have no image. The roster is a starting point, not a reliability score: editorial policies, corrections, original evidence, and cross-source checks matter more than an outlet label. [PBS feed directory](https://www.pbs.org/newshour/about/pbs-news-rss-feeds/), [Guardian feeds](https://www.theguardian.com/help/feeds), [ProPublica ethics](https://www.propublica.org/code-of-ethics), [The Markup ethics](https://themarkup.org/ethics), [Trust Project indicators](https://thetrustproject.org/).

| Reader category | Selected publisher feeds | Editorial purpose |
| --- | --- | --- |
| Broad reporting | [PBS News](https://www.pbs.org/newshour/feeds/rss/headlines), [BBC World](https://feeds.bbci.co.uk/news/world/rss.xml), [Guardian World](https://www.theguardian.com/world/rss) | Several independent desks for day-to-day context; expect some overlapping stories and wire copy. |
| Investigations | [ProPublica](https://www.propublica.org/feeds/propublica/main), [The Markup](https://themarkup.org/feeds/rss.xml) | Original accountability work with public editorial information. |
| Science | [Quanta](https://www.quantamagazine.org/feed/), [New York Times Science](https://rss.nytimes.com/services/xml/rss/nyt/Science.xml), [Ars Science](https://arstechnica.com/science/feed/), [Science News](https://www.sciencenews.org/feed), [ESA Space Science](https://www.esa.int/rssfeed/Our_Activities/Space_Science) | Specialist reporting at different depths; some publisher articles may require subscriptions. |
| Technology | [MIT Technology Review](https://www.technologyreview.com/feed/), [Guardian Technology](https://www.theguardian.com/technology/rss), [Ars Technica](https://feeds.arstechnica.com/arstechnica/index) | Research, technology policy and industry coverage; evaluate commercial stories individually. |
| Discovery | [The Conversation US](https://theconversation.com/us/articles.atom) | Researcher-written context that can be high volume; browse this category selectively. |

AP and Reuters were considered for broad reporting, but no publisher-owned public consumer RSS URL was verified. Their editorial standards remain useful when reading or comparing stories on their sites. NASA and JPL official feed directories were considered for primary-source science updates; direct candidate endpoints failed DNS or returned HTTP 403 from the desktop and were omitted. No source was selected on the basis of an automated outlet score. [AP principles](https://www.ap.org/about/news-values-and-principles/telling-the-story/), [Reuters standards](https://reutersagency.com/about/standards-values/), [NASA feed directory](https://www.nasa.gov/rss-feeds/).

NewsBlur is still the richest integrated discovery and training option, but its [self-host architecture](https://github.com/samuelclay/NewsBlur/blob/main/ARCHITECTURE.md) uses multiple databases and workers, a poor resource fit for this desktop homelab. ReactFlux can improve Miniflux article reading, including image viewing, but its [documented features](https://github.com/electh/ReactFlux) do not establish the requested headline-card grid. These are architecture-based judgments; a hands-on UI trial is still needed to judge personal fit.

## Answer

Use a feed reader as the home for sources you choose, and keep a separate, small discovery habit for stories outside those sources. **FreshRSS with Grid View is the current visual-reader trial**; Miniflux remains the smaller reader with stronger pre-ingest keep and block rules and a direct Karakeep action. The homelab keeps Miniflux's local PostgreSQL database and first-run account while the visual trial is assessed. [FreshRSS Grid View](https://github.com/FreshRSS/Extensions/tree/main/xExtension-GridView), [Miniflux filtering](https://miniflux.app/docs/rules.html), [API and OPML](https://miniflux.app/docs/api.html), [Karakeep integration](https://miniflux.app/docs/karakeep.html).

The existing homelab has a [Karakeep module](../../nix-homelab/modules/optional/karakeep.nix) and [catalog entry](../../nix-homelab/modules/catalog.nix). Its RSS subscription feature automatically saves new feed items. That makes it useful as a reading archive, but a high-volume news feed would fill the archive with articles you never chose. The desktop host configuration does not currently select Karakeep, and this research did not check whether the service is running. [Karakeep RSS announcement](https://github.com/karakeep-app/karakeep/discussions/632), [Karakeep feature list](https://github.com/karakeep-app/karakeep/blob/main/README.md).

The key limit is editorial. No reader can reliably turn arbitrary incoming links into trustworthy news. RSS gives control over subscriptions and ordering; the quality comes from source selection, separating reporting from opinion, and checking important claims against independent evidence. Automated filtering can reduce volume, but a strict keyword rule can also hide a story you would have wanted to see.

Self-hosting removes ads and recommendation pressure from the reader interface. It cannot remove ads embedded in a publisher's feed or website. Text extraction can make some articles easier to read, but it can fail, and it does not grant access through a paywall or override publisher terms. [Miniflux scraper behavior](https://miniflux.app/docs/rules.html), [Guardian feed terms](https://www.theguardian.com/help/feeds).

## Which problem are we solving?

| Need | Good approach | Why |
| --- | --- | --- |
| Read chosen sources in one quiet place | RSS or Atom reader | Source controlled, chronological, exportable subscriptions. |
| Catch important stories outside chosen sources | A short daily or weekly editor-selected briefing, or a coverage-comparison site | A fixed RSS list cannot show stories its sources ignore. |
| Follow a subject across many publications | Search/monitoring feed, for example GDELT, reviewed before promotion into the main reader | Broader recall, much more noise and weak source control. [GDELT DOC API](https://blog.gdeltproject.org/gdelt-doc-2-0-api-debuts/). |
| Assess contested coverage | Compare primary documents and several independent reports; optionally inspect outlet-level rating and ownership metadata | A publisher rating is context, not an article verdict. [Ground News methodology](https://ground.news/rating-system/). |
| Keep selected articles for later | Karakeep | Saving, tagging, search, and archiving are different tasks from scanning a daily feed. [Karakeep README](https://github.com/karakeep-app/karakeep/blob/main/README.md). |
| Publish a handpicked feed for yourself or others | A curated Karakeep list with RSS output | This is a different output from the raw subscriptions. Karakeep added RSS generation for lists in 0.25.0. [Release note](https://github.com/karakeep-app/karakeep/discussions/1561). |
| Track a valuable site without RSS | RSS-Bridge, then changedetection.io for a specific page | These create feeds or alerts, but scraping is fragile and adds maintenance. [RSS-Bridge README](https://github.com/RSS-Bridge/rss-bridge/blob/master/README.md), [changedetection.io README](https://github.com/dgtlmoon/changedetection.io). |

## Reader comparison

These are project-documented capabilities as retrieved on the review date. UI preference and actual feed compatibility need a hands-on trial.

| Reader | Strongest reason to choose it | Main cost or limit |
| --- | --- | --- |
| [Miniflux](https://miniflux.app/) | Small service; global and per-feed RE2 keep/block rules can reject items before storing them; scraping, OPML, API, mobile client protocols, and direct Karakeep saving. [Rules](https://miniflux.app/docs/rules.html), [Karakeep](https://miniflux.app/docs/karakeep.html), [API](https://miniflux.app/docs/api.html). | PostgreSQL required; source discovery is basic; categories and source tags are simpler than FreshRSS custom labels. |
| [FreshRSS](https://freshrss.org/) | Richer reader workflow: search queries, labels, dynamic OPML lists, XPath HTML feeds, extensions, and several databases including SQLite. [Manual](https://freshrss.github.io/FreshRSS/en/), [filters](https://freshrss.github.io/FreshRSS/en/users/10_filter.html), [extended OPML](https://github.com/FreshRSS/FreshRSS/blob/edge/docs/en/developers/OPML.md). | More settings and extensions to maintain. Its common filter actions mark articles read or favorite, whereas Miniflux documents pre-storage rejection. |
| [NewsBlur](https://www.newsblur.com/) | Strongest in-app training and broad discovery of this group, with feeds, mobile apps, OPML and story training. [Features](https://www.newsblur.com/features), [self-host architecture](https://github.com/samuelclay/NewsBlur/blob/main/ARCHITECTURE.md). | Its self-host stack uses multiple databases and worker services. Training is an explicit personal ranking system, which may or may not suit the desired reading style. |
| [CommaFeed](https://github.com/Athou/commafeed) | Clean interface and conventional reader features, including OPML, API, client compatibility, and auto-read rules. [README](https://github.com/Athou/commafeed/blob/master/README.md). | Less documented support for advanced discovery and a direct Karakeep workflow. |
| [Tiny Tiny RSS](https://tt-rss.org/) | Another self-hosted reader to test if its interface or a specific extension appeals. | This review did not obtain enough current first-party documentation to rank its maintenance cost confidently. |

The first trial selected Miniflux for its selective rules and direct Karakeep integration. The later request for an image-led interface changes the recommendation to FreshRSS with Grid View for the visual trial. NewsBlur remains worth considering if the actual goal is an intelligent personal newspaper with discovery inside the app, but its self-hosting cost is much higher. A hosted NewsBlur account is also an option if running that stack is undesirable. [Miniflux rules](https://miniflux.app/docs/rules.html), [FreshRSS filtering](https://freshrss.github.io/FreshRSS/en/users/10_filter.html), [NewsBlur architecture](https://github.com/samuelclay/NewsBlur/blob/main/ARCHITECTURE.md).

## Source quality is a process

Assess individual outlets and individual stories separately. A useful source roster mixes original general reporting, local reporting, subject specialists, investigative work, and a few primary-source feeds. It should include geographic and viewpoint diversity without treating two claims as equally supported merely because they come from opposite political camps.

For each candidate outlet, inspect several recent stories. Look for named reporters, original documents or interviews, links to evidence, clear distinctions between news and opinion or sponsored material, visible corrections, disclosed ownership and funding, and whether headlines fairly describe the article. The [Trust Project indicators](https://thetrustproject.org/) provide a practical checklist. Reuters and AP publish standards on sourcing, conflicts and corrections; those statements are useful evidence of editorial policy, though the existence of a policy alone does not prove every article follows it. [Reuters standards](https://reutersagency.com/about/standards-values/), [AP principles](https://www.ap.org/about/news-values-and-principles/telling-the-story/).

Use ratings as a second opinion. [AllSides](https://www.allsides.com/about/media-bias-rating-methods) measures perceived political bias. [Ad Fontes](https://adfontesmedia.com/methodology-white-paper/) scores both reliability and bias from sampled content. [Ground News](https://ground.news/rating-system/) combines outside outlet ratings and adds ownership and coverage comparisons. Its own method says ratings generally describe publications, not the specific article in front of you, and its political scale is framed around the United States. A center rating does not guarantee accuracy. These services are useful for finding disagreement and blind spots, not for automatic truth labels. Ground News and AllSides are adjacent proprietary services, not parts of the open-source reader stack.

For a claim that changes your view or a decision, read the original report, data, filing, speech, or paper when practical; then check independent reporting that does not simply repeat the same wire story. A [fact-checker following the IFCN commitments](https://www.ifcncodeofprinciples.poynter.org/the-commitments) can help with a specific disputed claim. This takes more effort than scoring a whole domain, but it addresses the actual claim.

## A high-quality first configuration

1. Start with about 15 to 25 feeds, grouped into **general reporting**, **local**, **your topics**, and **discovery**. These are trial sizes, not a platform limit. Subscribe to a publication's relevant section or author feed instead of its whole front page where possible. The Guardian documents section, keyword, and author RSS feeds; NASA publishes subject and mission feeds. [Guardian feed guide](https://www.theguardian.com/help/feeds), [NASA feed directory](https://www.nasa.gov/rss-feeds/).
2. Put trusted, low-volume original reporting in the main view. Put broad headlines, aggregators, and experimental sources in a separate discovery category. This avoids letting a prolific source dominate the reading queue.
3. Browse titles and summaries first. Save only articles worth finishing or referencing to Karakeep. Keep Karakeep's automatic RSS import for a few low-volume feeds where saving every item is intentional. [Miniflux Karakeep setup](https://miniflux.app/docs/karakeep.html), [Karakeep RSS behavior](https://github.com/karakeep-app/karakeep/discussions/632).
4. After a week, add narrowly targeted Miniflux block rules for repeated noise such as shopping roundups. Prefer feed-specific rules; global rules can silently remove important coverage. Check rejected patterns when refining the feed. [Miniflux rule order and fields](https://miniflux.app/docs/rules.html).
5. Keep a weekly discovery pass from a human-edited briefing, another region's public broadcaster or newspaper, and a coverage comparison tool. Promote a newly found source only after sampling its work. Add RSS-Bridge only when an important source lacks a native feed. [RSS-Bridge](https://github.com/RSS-Bridge/rss-bridge/blob/master/README.md).
6. Export OPML regularly, back up the reader database, and record why each feed is on the list. OPML preserves the subscription roster; application-specific rules and read state may require database backups. [Miniflux API and OPML](https://miniflux.app/docs/api.html), [FreshRSS backup guidance](https://freshrss.github.io/FreshRSS/en/admins/05_Backup.html).

The initial source roster should be personalized. A sensible test set includes one or two wire or public-service newsrooms for broad coverage, at least one local newsroom, a substantive investigative publication, specialist publications for the user's interests, and direct feeds for primary releases. AP and Reuters are examples of newsrooms with published editorial standards, but the existence and terms of their consumer RSS feeds must be verified before configuring them. Do not assume a syndication or scraper feed is permitted. A concrete verified feed example is the [Guardian's section RSS](https://www.theguardian.com/help/feeds); [NASA's feed directory](https://www.nasa.gov/rss-feeds/) supplies official primary-source topics.

An initial source menu, to sample rather than subscribe to wholesale:

| Slot | Candidate and why it is worth sampling | Delivery verified here |
| --- | --- | --- |
| Broad reporting | [AP](https://www.ap.org/about/news-values-and-principles/telling-the-story/) or [Reuters](https://reutersagency.com/about/standards-values/) publish sourcing and correction standards. | Read on site or find a permitted publisher feed; this review did not verify a current consumer RSS endpoint. |
| Section-level general news | [The Guardian](https://www.theguardian.com/help/feeds) supports RSS for sections, keywords, and author pages. | Official RSS guide. |
| Accountability reporting | [ProPublica](https://www.propublica.org/code-of-ethics) publishes an ethics policy and a [visible corrections page](https://www.propublica.org/corrections). | [Official newsletters](https://www.propublica.org/newsletters) verified; a current article RSS endpoint was not verified. |
| Explanation by specialists | [The Conversation](https://cdn.theconversation.com/static_files/files/1929/Global_Editorial_Guidelines.pdf) has a published policy that authors write within their research expertise. | Check a relevant section's feed or newsletter before subscribing. |
| Primary-source updates | [NASA](https://www.nasa.gov/rss-feeds/) has official technology, aeronautics, mission, and release feeds. | Official RSS directory. |
| Local accountability | One newsroom covering the user's actual city or region, selected after checking its reporters, ownership, corrections, and published work. | Depends on location. |

## Adjacent options and when they fit

- **Newsletter-first reading.** Some of the best editorial selection arrives by email. If the preference is a few carefully edited digests per week, use a separate mail folder and skip hosting a reader at first. [Kill the Newsletter](https://github.com/leafac/kill-the-newsletter) can turn mail into Atom, but self-hosting it introduces mail operations and another point of failure.
- **Coverage comparison.** [Ground News](https://ground.news/rating-system/) is useful for seeing which outlets covered a story and how it was framed. It is an external proprietary tool and does not replace the personal archive.
- **Subject monitoring.** [GDELT DOC](https://blog.gdeltproject.org/gdelt-doc-2-0-api-debuts/) searches a much wider news corpus. Use it for periodic research or narrow alerts; raw matches do not carry an editorial quality guarantee.
- **Page monitoring.** [changedetection.io](https://github.com/dgtlmoon/changedetection.io) can watch an official page that lacks a feed. It answers "did this page change?" rather than "is this article good?"
- **Feed generation.** [RSSHub](https://github.com/DIYgod/RSSHub) has many community-maintained routes for sites without RSS. Treat each route as a third-party scraper that can break when the site changes; use a publisher's own feed when it exists.
- **Custom automation.** [Huginn](https://github.com/huginn/huginn/blob/master/README.md) can combine feeds, filters, and digests. Its service and security complexity is hard to justify before a simple reader has demonstrated a missing workflow.

## Validation and limits

The initial BBC World, Guardian World, ProPublica, New York Times Science, and Ars Technica Science feed endpoints returned valid XML on 2026-09-24. The Miniflux NixOS VM test passed with a local fixture feed: it checked database startup, account authentication, import, private listener, and persistence of a user-deleted subscription. The earlier desktop configuration built and was activated on 2026-09-24. On the running host, Miniflux and PostgreSQL were active, the first-run feed import succeeded, and the listener was confined to loopback. A later live TLS check verified the certificate and Miniflux HTTPS response after ACME renewal; the earlier certificate warning is resolved. The packaged FreshRSS 1.30.0 visual variant built, its NixOS VM test passed with bootstrap, OPML import/export, private listener, privacy header and preservation of a changed user setting, and the full desktop configuration built. The package-wide flake check encountered an invalid store path in another concurrently edited package, `jellyfin-plugin-moonbase`; the focused FreshRSS package independence evaluation passed. FreshRSS was activated and authenticated browser checks were completed on 2026-09-26. Publisher thumbnails loaded, dark-mode text was readable, bookmarking persisted after reload, and the narrow layout had no horizontal overflow. Upstream pages were reviewed on 2026-09-24; publisher terms and third-party rating methods can change. Revisit the choice after a two-week trial with the user's actual reading volume.

## Implication for this repository

The [optional Miniflux module](../../nix-homelab/modules/optional/miniflux.nix) retains the original reader and its PostgreSQL state. The [FreshRSS module](../../nix-homelab/modules/optional/freshrss.nix) and [desktop selection](../../hosts/nixos/desktop/local/homelab/news.nix) add a separate visual reader behind the private HTTPS proxy. The original reusable `freshrss-visual` package belonged to nixpkgs-personal because the official Grid View bundle and defaults form a named package variant. No root overlay is needed. Updating the older Nixpkgs FreshRSS recipe is a separate upstreamable change; the variant's release pin can be removed when its upstream input catches up. Its SQLite state is in the homelab recovery inventory. The fourteen starter feeds follow the user's chosen broad news, science and technology emphasis; later subscription choices belong to the FreshRSS account. Read state does not automatically migrate between readers. The [module guide](../../nix-homelab/docs/optional-services.md#freshrss-visual-reader) covers access, credentials, backup and iPhone use.

## Visual reader repair review, 2026-09-26

FreshRSS with official Grid View remains the selected native stack. SQLite,
PHP-FPM and native search avoid another application runtime.
[FriRSS](https://github.com/Fripix/Frirss) offers a richer PWA but adds a Node
service and client-side search scans. [Nextflux](https://github.com/electh/nextflux)
is a static Miniflux frontend with a documented desktop emphasis. Trial either
only if a concrete missing workflow justifies the added maintenance.

The pinned [official extension](https://github.com/FreshRSS/Extensions/tree/47db9391d0c66d3e15ad8bd4fa44e477fabdae1e/xExtension-GridView)
needed repairs for quote escaping, XML-escaped image URLs, native article IDs,
theme colors, and asynchronous script initialization. The personal package tests its installed JavaScript and adds
an accessible stylesheet. Content hashes replace mtime-based browser cache
keys because Nix normalizes mtimes. Remove individual repairs when equivalent
upstream fixes are reviewed; no root overlay is needed.

Publication sorting is descending, with 30 articles per page, lazy images,
automatic light/dark mode, private saved queries and reading labels.
[FreshRSS filters](https://freshrss.github.io/FreshRSS/en/users/10_filter.html)
distinguish publication time (`pubdate`) from discovery time (`date`); Today
and This week use publication time. Topic queries match headline words and
are starting points rather than semantic classifiers.

Additional official feeds returned valid XML and image metadata during review:
[Science News](https://www.sciencenews.org/feed),
[ESA Space Science](https://www.esa.int/rssfeed/Our_Activities/Space_Science),
and [Ars Technica](https://feeds.arstechnica.com/arstechnica/index). ESA is an
institutional primary source; compare claims with independent reporting.
Missing or low-resolution publisher images remain possible. Open Graph fetching
is prohibited in this variant, including its authenticated AJAX endpoint:
the pinned extension follows redirects without private-address validation.
Package PHP checks verify rejection and late user configuration loading.

FreshRSS and Miniflux VM tests, homelab configuration-contract checks, the
personal repository's `just check`, and the desktop build passed. Miniflux's
existing account was corrected from oldest-first to newest-first; its media
proxy now includes HTTPS images.

The final authenticated browser trial used a 390-by-844 viewport: image cards
fit without horizontal overflow, the 44-pixel menu button opened and closed
the source sidebar, and sticky controls were active. Desktop and mobile
screenshots were inspected privately. This is responsive-browser validation,
not a physical iPhone Safari or native-client test.
