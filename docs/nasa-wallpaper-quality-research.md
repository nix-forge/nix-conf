# NASA imagery that is good enough for a desktop

## Decision

Make the **NASA Image and Video Library** the default NASA wallpaper source. It is the better catalogue for the desired result: mission and space-agency photography, with an original-asset manifest for each result. Keep the **Scientific Visualization Studio (SVS)** only as a deliberately opt-in, separately curated source for visualizations. It is not a photo archive, and 4K dimensions do not make an educational graphic, chart, rendered model, or video frame suitable as desktop art.

The supplied example is the locally cached SVS record **4313, “Earth System Science Cartoon Schematic”**. It is a designed, text-bearing Solar System graphic rather than a photographic scene. The old fetcher can choose this class of asset because it searches SVS `Visualization` records and recursively accepts *any* nested `Image` that meets 3840x2160. It has no positive photographic criterion and does not limit itself to a page's intentionally presented still. See [`wallpaper-fetch-nasa.sh.in`](../modules/home/desktop/scripts/wallpaper-fetch-nasa.sh.in).

## What the official APIs provide

| Source | Best use | Discovery and download contract | Quality implication |
| --- | --- | --- | --- |
| [NASA Image and Video Library API](https://images.nasa.gov/docs/images.nasa.gov_api_docs.pdf) | Default: mission, astronaut, spacecraft, Earth, telescope, and planetary photography | `GET https://images-api.nasa.gov/search` supports `media_type=image`, free-text `q`, `keywords`, `title`, `description`, `center`, dates and pagination. Each result has a `nasa_id`; `GET /asset/{nasa_id}` returns the original and derivative URLs. | Search previews are only discovery material. Resolve the asset manifest, choose `~orig` (or the largest acceptable raster), then inspect the downloaded file. |
| [NASA Scientific Visualization Studio API](https://svs.gsfc.nasa.gov/help/) | Opt-in: specifically selected data visualizations and rendered Earth/space scenes | `GET /api/search/?…` mirrors SVS search parameters; `GET /api/{page-id}/` returns the full page, including keywords, credits, media records, URLs and dimensions. | SVS says most newer visualizations are 4K, but it also contains infographics, animations, data products, and title cards. Resolution is necessary but cannot be the aesthetic selection rule. |

The Image Library search API requires at least one parameter. Useful server-side filters are `media_type=image`, subject terms (`q`, `keywords`, `title`, or `description`), `center`, `year_start`, `year_end`, `page`, and `page_size`. The official API documentation specifies image/video/audio as its media types and its asset endpoint as the way to retrieve the original and derivatives.

SVS officially documents a free JSON API, `limit` (default 100, maximum 2000) and `offset` pagination. Its page API is important if SVS remains enabled: a search result is a summary, whereas the page response exposes the media item's real pixel dimensions and credits. SVS describes its own material as public domain unless otherwise noted, and notes that newer work is commonly 4K; that is a download and reuse advantage, not an editorial-quality guarantee.

## Recommended admission policy

### 1. Use a photo-first NASA Library search plan

Maintain a small shuffled list of contemporary photographic subject searches, each sent with `media_type=image` and a `year_start` of 2000. This avoids passing a high-resolution scan of a 1960s or 1970s image off as a high-quality modern photograph. Good starting phrases are:

- `NASA Earth Observatory`, `Earth from International Space Station`, `aurora from International Space Station`;
- `Hubble Space Telescope image`, `James Webb Space Telescope image`, `planetary nebula Hubble`;
- `Artemis launch photography` or `NASA launch photography`.

Fetch a candidate's `/asset/{nasa_id}` manifest. Prefer a URL named `~orig`; fall back only to another image derivative whose decoded pixels pass the same gate. Never use the `~thumb`, `~small`, `~medium`, preview, or search-card asset as a wallpaper source. The manifest may expose plain `http` URLs in addition to the `https` asset links returned during search, so convert only the known `images-assets.nasa.gov` scheme to HTTPS before downloading; reject another host or a downgrade.

### 2. Gate the *actual downloaded pixels*

For the physical 4K desktop profile, require all of the following before an image enters the collection:

1. A locally decoded raster at least 3840 by 2160 pixels.
2. Landscape orientation and a configurable desktop-friendly aspect-ratio range (the current non-16:9 setup uses `1.40 <= width / height <= 2.40`; raise the minimum to `1.60` for a 16:9-only collection).
3. A displayable image MIME type, bounded download size, and no upscaling.
4. After any deliberate conversion, a final image that still passes the pixel and aspect-ratio checks.
5. Deduplication by final-file digest and a sidecar recording `nasa_id`, title, source URL, dimensions, original filename, center/credit fields, and the policy decision.

This prevents the common error of treating catalogue metadata or an API preview's reported dimensions as proof of the downloaded file's quality.

### 3. Exclude graphics before download, and optionally validate visual text

Search metadata is not a perfect classifier, but it is an effective inexpensive negative filter. Case-insensitively reject a candidate when title, description, keywords, or creator fields contain terms such as:

```text
animation, artist's concept, artwork, chart, concept art, diagram,
educational, emblem, graphic, illustration, infographic, insignia, logo,
map, mission patch, model, patch, poster, rendering, schematic, simulation,
timeline, title card, visualization
```

Do **not** reject broad subject words such as `solar system`, `earth`, or `science`: they are useful for both excellent photographs and poor graphics. The discriminators are media form and text-bearing design language. A later optional quality layer can run local OCR and reject images with substantial overlay text; it should be advisory or conservative, because NASA photographs of spacecraft displays and signs can contain legitimate small text.

### 4. If SVS is retained, make it a strict separate adapter

SVS should not share the Image Library's default pool. Its adapter should:

- query an allowlist of narrowly scenic subjects and inspect the full page API;
- select only direct image media records with numeric dimensions, not an arbitrary recursively found image and not the site's preview;
- require the same decoded 4K landscape gate and a stronger negative vocabulary (`map`, `model`, `simulation`, `visualization`, `graphic`, `title`, `slate`, `credits`, `caption`, and the terms above);
- record the exact page ID, asset URL and credits; and
- skip pages with an explicit third-party/copyright notice.

SVS is still valuable for a user who specifically wants data-driven space visuals. Its own documentation says it offers higher-resolution TIFF/TIF/EXR stills as well as browser-friendly JPG/PNG, so the adapter can choose a supported large raster or make an explicit, verified conversion. It should not silently turn every 4K frame available on an SVS page into a wallpaper.

## Rights and provenance

NASA's current [Images and Media Usage Guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/) state that NASA content is generally not subject to US copyright and asks that NASA be acknowledged. The same policy explicitly says third-party material may appear on NASA sites and will be identified with its copyright holder; NASA's use does not transfer reuse rights. It also treats the NASA insignia, logotype, identifiers, and imagery associated with them differently from ordinary media.

Therefore, an automated source must not label every result "public domain" unconditionally. Save the returned metadata and page credits, reject an explicit third-party/copyright restriction, and expose provenance through the existing wallpaper-info path. For a personal desktop this is straightforward, but it keeps the local library honest and makes later sharing safe to assess.

## Implementation order

1. Add a `nasaLibrary` source and enable it in the interactive desktop profile. Preserve the present local cache, rotation, permissions, checksum, and decoded-image validation behaviour.
2. Change the default configuration so `nasaSvs.enable = false`; retain it only as a documented opt-in. Do not make SVS failure block rotation of already accepted wallpapers.
3. Add photo-form rejection terms and the original-asset manifest workflow to the new Library fetcher. Add fixture tests for a thumbnail-only record, a portrait original, a text/infographic record, a too-small original, and a valid landscape original.
4. Tighten the SVS fetcher independently if it remains available: inspect only the intended media structure, then apply the stronger visualization policy.
5. Add a review queue/favourite flag later if purely automated selection still produces occasional images the owner does not want. No metadata-only policy can fully encode personal taste.

This direction uses NASA's photo-oriented library for what it is best at and keeps SVS available for its distinct, legitimately useful but much less predictable class of imagery.
