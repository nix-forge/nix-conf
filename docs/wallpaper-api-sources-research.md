# Wallpaper image API sources

## Decision summary

The current NASA SVS downloader should not choose a random visualization and
then accept its `main_image`. SVS is a scientific-visualization archive, so
that policy naturally admits diagrams, title cards, charts, and video frames.
Use it only with an explicit aesthetic policy, or make the NASA Image and Video
Library the default NASA photo source.

For an automatic, local 4K wallpaper library, the most suitable sources are:

| Source | Recommendation | Reason |
| --- | --- | --- |
| Wikimedia Commons Featured Pictures | Opt-in/default candidate | Free API, broad subject matter, community quality signal, original dimensions and licence metadata. |
| Smithsonian Open Access | Credential-backed/default when provisioned | CC0 images from museum, archive, science, and natural-history collections; API exposes an explicit high-resolution rendition and dimensions. |
| NASA Image and Video Library | Replace generic SVS selection | Actual mission photography and a downloadable original-asset manifest. |
| NASA SVS | Keep, but narrowly curated | No key and much new work is 4K; use only image assets passing a strong quality policy. |
| Unsplash | Optional, terms-aware | Excellent discovery metadata and landscape filter, but its API rules require use of returned hotlinks and download tracking. |
| Pixabay | Optional only after full-API approval | Its ordinary documented image links are below 4K; the original/full-HD URLs have access restrictions. |
| Pexels | Exclude | Its API terms prohibit making Pexels content available as a wallpaper application. |

All accepted files should be decoded locally before admission. A source-reported
resolution is a useful pre-filter, not proof that the downloaded asset is
suitable.

## NASA: selecting images that belong on a desktop

### Preferred NASA source: Image and Video Library

The [NASA Image and Video Library API](https://images.nasa.gov/docs/images.nasa.gov_api_docs.pdf)
is REST/JSON at `https://images-api.nasa.gov`. Its `search` endpoint supports
`media_type=image`, free-text `q`, `keywords`, `title`, `description`, date
ranges, and pagination. Each result contains a `nasa_id`; `GET
/asset/{nasa_id}` returns an asset manifest with the original and derivative
download URLs. This is a much better input than an SVS preview because the
fetcher can choose the original, decode it, and reject it if it is not large
enough.

No API key is specified in the Library API documentation. It should therefore
remain keyless, with conservative request volume, timeouts, and a local cache.
NASA's API-key rate limits at `api.nasa.gov` do **not** establish a limit for
this separately hosted `images-api.nasa.gov` service. Do not assume that an
`api.nasa.gov` key authorizes or rate-limits the Image Library.

Use a small, rotating set of subject queries rather than a catch-all search:

- `aurora`, `earth from space`, `earth observatory`, `landsat`, `hubble`,
  `james webb`, `nebula`, `galaxy`, `eclipse`, `moon`, and `mars landscape`;
- restrict every request to `media_type=image`;
- fetch the asset manifest, prefer an `~orig` image asset, and inspect actual
  dimensions and MIME type after download;
- reject title/description/keyword matches such as `diagram`, `chart`,
  `graph`, `infographic`, `logo`, `poster`, `illustration`, `concept`,
  `timeline`, and `artist's concept` (the apostrophe variants too);
- require at least 3840 pixels wide and 2160 pixels high, a landscape aspect
  ratio, and no forced upscaling. A 16:9 target may accept a configurable
  source range such as 1.6–2.4, then use the renderer's crop/fit policy;
- retain `nasa_id`, title, asset URL, credit, and the licence decision in a
  0600 sidecar JSON file next to the downloaded image.

The [NASA media guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/)
say NASA content generally is not subject to US copyright and ask users to
acknowledge NASA. They also say third-party copyright-protected material may
appear and is identified with its copyright holder. The downloader must reject
an asset where its source record identifies third-party restrictions; it must
not turn NASA's general policy into a blanket licence claim.

### Retain NASA SVS only with an explicit quality gate

SVS offers free public JSON `GET` APIs: the documented search endpoint is
`https://svs.gsfc.nasa.gov/api/search/`, and `GET /api/{page-id}/` returns the
complete visualization page, including `main_image` dimensions, credit, title,
keywords, and other metadata. The [SVS help and API documentation](https://svs.gsfc.nasa.gov/help/)
states that most newer visualizations are published in 4K (and that some higher
resolution stills are TIFF/TIFF/EXR). It also describes SVS content as public
domain unless otherwise noted.

SVS search results contain only a summary; perform the page request before
downloading. Admit an item only if:

1. the result is a visualization/image, not a produced video, gallery card, or
   audio item;
2. `main_image.width >= 3840`, `main_image.height >= 2160`, and the aspect
   ratio is accepted;
3. title, description, and keywords do not trigger the rejection vocabulary
   above; and
4. the page has no non-public-domain notice.

The resulting images will still be science visualizations, not general nature
photography. The source should be framed as a space/Earth-science collection,
not as the main source of generic desktop photography. Queries focused on
`aurora`, `earth`, `landsat`, `hubble`, `webb`, and `nebula` are appropriate;
the configuration should let the user select the allowed query list in Nix.

SVS documents a default search page size of 100, a maximum `limit` of 2000,
and offset pagination. It does not publish a numeric public request quota in
that documentation. Use a small page size, one candidate-selection pass per
scheduled fetch, conditional retries with exponential backoff, and no parallel
crawling.

## Other sources

### Smithsonian Open Access: a strong credential-backed art and nature source

The [Smithsonian Open Access API](https://www.si.edu/openaccess/devtools) uses
a free API key from api.data.gov. Its search response distinguishes collection
records and individual media, records CC0 access at both levels, and provides
explicit `High-resolution JPEG` or `High-resolution TIFF` rendition URLs with
pixel dimensions. The [Open Access FAQ](https://www.si.edu/openaccess/faq)
confirms that the programme provides CC0 2D JPG and TIFF media, while records
that are not openly licensed can expose metadata without a downloadable media
file.

The adapter should search intentionally visual subjects such as landscape,
seascape, national parks, waterfalls, forests, and botanical material. It must
then require CC0 on the object and media, a named high-resolution rendition,
at least 3840x2160 decoded pixels, a desktop-shaped landscape aspect ratio,
and a bounded original download. Avoid the API's delivery thumbnail URLs. The
high-resolution download endpoint currently redirects to Smithsonian's object
storage, so allow redirects only when they remain HTTPS and validate the final
download's decoded MIME type and dimensions.

Store the data.gov key as a `nix-seal` systemd credential. This keeps it out
of the Nix store, process arguments, normal environment, and service logs.
The fetcher should be absent while the encrypted secret is pending, then be
enabled declaratively after provisioning; this avoids a background unit that
can only fail because its credential is unavailable.

### Wikimedia Commons: strongest keyless, non-space source

Wikimedia's Action API generally needs no credential. Use
[`categorymembers`](https://www.mediawiki.org/wiki/API:Categorymembers) to
enumerate a tightly selected category such as Featured Pictures or Quality
Images, then [`imageinfo`](https://www.mediawiki.org/wiki/API:Imageinfo/en)
with `iiprop=url|size|dimensions|mime|extmetadata`. That exposes an original
download URL, pixel dimensions, MIME type, file size, author, and licence
metadata. [Featured Pictures](https://commons.wikimedia.org/wiki/Featured_Pictures)
are selected as especially valuable images; [Quality Images](https://commons.wikimedia.org/wiki/Commons:Quality_images/en-gb)
are selected for technical quality. Either is a material improvement over a
random Commons query.

Commons has per-file licences, not one Commons-wide licence. Its
[reuse guidance](https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia/en)
requires complying with each file's attribution/licence terms. The safe
automated default is public-domain or CC0 only; save the exact `extmetadata`
licence, creator, source page, and attribution in a sidecar. If supporting
CC-BY/CC-BY-SA later, expose the required attribution in a user-accessible
`wallpaper-info` command rather than silently discarding it.

The [Wikimedia API policy](https://meta.wikimedia.org/wiki/API_Policy_Update_2024)
requires a descriptive User-Agent and asks clients to respect dynamic rate
limits. The downloader should therefore identify its project/version and
contact URL, serialise requests, cache results, honour `Retry-After`, and
back off on 429/5xx responses.

### Unsplash: viable only if its API usage model fits the product

The [Unsplash API documentation](https://unsplash.com/documentation) requires
an account/application and a public `Client-ID` (or OAuth for user actions).
Demo applications receive 50 requests per hour; production access is granted
after review. `GET /search/photos` provides `orientation=landscape`,
`content_filter=high`, `order_by=relevant|latest`, source `width`/`height`,
URLs, and photographer identity. These fields make good pre-selection inputs.

However, Unsplash requires applications to use the dynamically returned photo
URLs, send the download event to `links.download_location` when a photo is
downloaded, and attribute the photographer and Unsplash. Those requirements
make an opaque local cache less straightforward than a normal file mirror.
Treat Unsplash as a disabled-by-default source until the implementation has a
clear compliance path: per-file attribution sidecars, download-event handling,
and terms review. A personal Nix module should take its `Client-ID` from a
secret file, never from a Nix expression or store path.

### Pixabay: good filters, insufficient guaranteed 4K access

The [Pixabay API](https://pixabay.com/api/docs/) requires a key obtained after
login and documents 100 requests per 60 seconds per key. Its image endpoint
can filter `image_type`, `orientation=horizontal`, categories such as nature
and backgrounds, `min_width`, `min_height`, `editors_choice`, `safesearch`,
and popularity/date ordering. Responses include dimensions and file size.

The same documentation limits ordinary `largeImageURL` to 1280px and
`fullHDURL` to 1920px; original `imageURL`/full-HD access requires approved
full API access. It is not a reliable 4K source unless that approval has been
obtained and the downloaded original passes local validation. Store the key in
a credential file and use the source only when explicitly enabled.

### Pexels: do not integrate

The [Pexels API documentation](https://www.pexels.com/api/documentation/)
requires an API key and provides technically attractive filters: landscape
orientation, `size=large` (24 megapixels or more), colour, and curated search.
It reports original dimensions, photographer details, and original URLs.
Its default rate limit is 200 requests/hour and 20,000/month.

Nevertheless, the Pexels API documentation explicitly prohibits using the API
to make Pexels content available as a wallpaper application. The
[Pexels licence](https://www.pexels.com/legal-pages/license/) permits personal
desktop use, but that does not override the API restriction for an automated
wallpaper product. Do not add Pexels to a general/open-source wallpaper source
aggregator; this avoids a clear terms violation.

## Source-module and service requirements

Every remote source should be a standalone module with the same contract:

- `enable`, `queries`/categories, `minWidth`, `minHeight`, allowed aspect
  range, `maxFileSizeMiB`, `maxImages`, cadence, and source-specific enablement
  in Nix—no GUI source picker;
- a credential **file path** option where a source needs a key. The path is
  read only by the user service, is not copied into the Nix store, and uses
  mode 0600. Do not put keys in `environment.variables`, generated scripts, or
  units;
- a single request-at-a-time service with strict curl timeouts, HTTPS-only
  URLs, redirect limits, bounded downloads, content-type/decoder validation,
  atomic file moves, and 0700 cache/state directories;
- a provenance sidecar including source ID, page URL, download URL, title,
  creator/credit, licence decision, downloaded time, image dimensions, and a
  content hash;
- a per-source quota and eviction that never deletes the current wallpaper;
  rotation operates only on locally validated images and never has network
  access.

This separation preserves performance and offline operation, limits secret
exposure to the service that needs it, and makes every source independently
enableable while sharing the same trusted local wallpaper cache.
