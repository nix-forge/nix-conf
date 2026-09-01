# Smithsonian Open Access: desktop-quality admission policy

## Finding

The pictured ledger is consistent with a weakness in the current Smithsonian
adapter, not a resolution failure. The adapter asks the collection-wide search
index for broad terms such as `landscape` and `botanical`, then admits any CC0
high-resolution landscape image unless a small title/description deny-list
matches. Smithsonian Open Access deliberately includes material from museums,
research centres, libraries, and archives; a high-resolution 2D scan can
therefore be a ledger, book spread, specimen sheet, or other research record.
Neither a CC0 flag nor 4K dimensions is an aesthetic-quality signal.

Smithsonian confirms that Open Access covers 2D images as well as data and 3D
assets, and that available 2D download formats include JPG and, where present,
TIFF. It also explicitly notes that the API includes metadata for many kinds of
collection objects. [Open Access FAQ](https://www.si.edu/openaccess/faq)

## What the first-party API exposes

The official Smithsonian Open Access API documents a general `search` call,
the `edanmdm` record type, `objects` versus `archives` row groups, and the
`object_type`, `online_media_type`, and `unit_code` search-term categories.
The API defines the `objects` group as collection objects/artifacts/specimens
and `archives` as archival collection/item records, so `row_group=objects` is
a worthwhile baseline but is not sufficient to exclude a scanned document
held as an object. The `q` parameter supports fielded search, and `fqs` accepts
JSON-array filters with AND/OR semantics; use those documented mechanisms for
positive constraints rather than relying on an undocumented negative-query
operator. [Open Access API documentation](https://edan.si.edu/openaccess/apidocs/)

The official terms endpoint exposes controlled vocabulary for object type,
online-media type, and unit code. Its online-media terms include document-risk
classes such as `Scanned books`, `Full text documents`, `Catalog cards`, and
`Finding aids`, alongside visual values such as `Images` and `3D Models`. The
official EDAN schema describes `indexedStructured.object_type` as the
form/genre/type classification and gives `book`, `painting`, and `diary` as
examples. [EDAN Object Records schema](https://sirismm.si.edu/siris/EDAN_IMM_OBJECT_RECORDS_1.09.pdf)

The current API response for an `edanmdm` object also carries:

- `unitCode` and `content.descriptiveNonRepeating.unit_code` — the owning
  Smithsonian unit;
- `content.descriptiveNonRepeating.data_source` and `record_link` — useful
  provenance for a review queue and for debugging an unwanted result;
- `content.indexedStructured.object_type`, `topic`, and
  `online_media_type` — structured class and subject data;
- `content.freetext.objectType`, `physicalDescription`, `name`, `notes`, and
  `description` — additional display and classification text; and
- `descriptiveNonRepeating.online_media.media[].resources[]`, including the
  named high-resolution rendition, URL, and source-reported dimensions.

The public client lists `random` as a search sort, so randomisation should take
place only *after* a strict semantic query/gate. It must not be treated as a
quality selector. [Official Smithsonian Open Access client README](https://github.com/Smithsonian/smithsonian-openaccess/blob/main/README.md)

Smithsonian's developer page says the public API exposes field, department,
and data-type documentation, and distinguishes CC0 collection metadata from
the separately available media file. This supports using the structured record
metadata for admission, while continuing to validate the downloaded pixels.
[Open Access Developer Tools](https://www.si.edu/openaccess/devtools)

## Recommended policy

### Make the source intentionally narrow by default

Use two separately configurable collections rather than a catch-all
"Smithsonian" source:

1. **Fine art**: query `object_type:Paintings` and optionally
   `object_type:Photographs`, with scenic subject queries such as `landscape`,
   `seascape`, `forest`, `waterfall`, and `garden`.
2. **Nature photography**: enable only with an explicit unit allow-list and a
   photographic object-type allow-list. It should not silently include scans
   from libraries and archives just because they match a nature word.

The API accepts structured query clauses such as `object_type:Paintings` and
`unit_code:SAAM`; these were verified against the live public API with its
documented demo credential. Prefer values retrieved from the official terms
endpoint, then use `q`/`fqs` to apply the fielded constraints. Keep
`type=edanmdm`, `row_group=objects`, and `online_media_type:Images` as
baseline filters. `Images` only says the record has image media; it does not
say that the image is a scenic photograph rather than a scan.

For a conservative default, require an allowed `indexedStructured.object_type`
of `Paintings` or `Photographs` **after** the server search. A painting is a
digitised artwork rather than a camera photo, but it meets the desired desktop
art use case; expose it as a separate `art` toggle if photographic-only output
is desired. Do not positively admit `Books`, `Documents`, `Manuscripts`,
`Ledgers`, `Sketchbooks`, `Albums`, `Maps`, `Plans`, `Plates`, `Prints`,
`Drawings`, `Graphic Arts`, `Technical Drawings`, or `Specimens`.

### Add a structured deny-list, not just title words

Before any download, combine and normalize title, structured object type,
physical description, notes, description, and accessibility text. Reject a
record if any of these terms occurs in that combined metadata:

```text
account book, album, architectural drawing, blueprint, book, botanical plate,
calendar, catalog, chart, correspondence, document, field book, form, graph,
handwritten, ledger, letter, manuscript, map, notebook, page, plan, plate,
proof, register, score, sketchbook, specimen sheet, technical drawing
```

Some words, especially `plate`, `drawing`, and `specimen`, can describe an
image a user might personally like. That is why the positive object-type gate
is the primary control: the deny-list is a defence-in-depth measure, not the
only classifier.

### Preserve the existing hard technical and rights gates

Retain CC0 checks at **both** object and media level, accept only a named
high-resolution JPG/TIFF rendition, decode the downloaded file locally, and
require the configured 4K/minimum dimensions and landscape aspect ratio. The
FAQ confirms CC0 is the programme's public-domain designation and recommends
recording title, author, source, licence, and source URL as a useful minimal
credit. [Open Access FAQ](https://www.si.edu/openaccess/faq)

Do not attempt to infer quality from source-reported dimensions alone. A
ledger scan can be very large; decoded pixels only establish that the asset is
technically displayable.

### Make false positives recoverable

Store the source record ID, title, unit code, object type, record URL, query,
and accept/reject reason in the existing sidecar. Add a local blocklist keyed
by `source_id` and media ID, checked before selection. When the user rejects a
wallpaper, add it to that list and immediately rotate away; it should never be
re-downloaded. This provides reliable personal taste control without an online
account, GUI picker, or a brittle attempt to fully automate aesthetics.

## Implementation order

1. Inspect the sidecar for the shown wallpaper to confirm its source; do not
   assume Smithsonian when several sources share one rotation directory.
2. Purge or blocklist the identified file and rotate to a validated existing
   wallpaper.
3. Add `allowedObjectTypes`, optional `allowedUnitCodes`, and the structured
   rejection vocabulary to the standalone Smithsonian module. Defaults should
   be the conservative fine-art profile above, with Nix options for users who
   deliberately want a broader collection.
4. Make the fetcher include structured object types and provenance fields in
   its candidate JSON and apply the new gates before a high-resolution asset is
   downloaded.
5. Test with fixtures for a ledger/book scan, a high-resolution map, a
   high-resolution painting, and a high-resolution photograph; only the last
   two should pass the conservative default. Then manually run the service,
   inspect its sidecar, and confirm the next wallpaper is not a rejected file.

This policy does not claim that every accepted art photograph is universally
beautiful. It prevents the demonstrated catalogue-document failure mode while
leaving source composition and strictness declarative in Nix.
