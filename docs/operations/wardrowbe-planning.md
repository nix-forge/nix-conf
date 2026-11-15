# Garment reviews and wardrobe planning

The paired Wardrowbe packages add a **Wardrobe planning** page under
`/dashboard/planning`. It is available from desktop and mobile navigation, and
from an individual garment's detail view. This is a local application extension
to the upstream version described in [the capability research](../research/wardrowbe-capabilities-research.md).

## Review an individual garment

Select the garment by its photo and name. Record its current condition, fit,
comfort, fabric composition from its label, measurements with units, construction,
defects, care requirements and notes. Choose keep, repair, alter, replace or
retire, with an explicit priority and estimated repair cost where known.

The availability control determines whether the garment can appear in new
recommendations and pairings. A garment awaiting an upgrade can remain available.
Retired and unusable garments are unavailable. Older garments stay usable unless
their recorded condition or the owner's decision says otherwise.

Use suitable occasions and climates to confirm where a garment works. For
example, a requirement for `work` in a `warm` climate should use the same terms
as the corresponding garment reviews. Unconfirmed suitability is reported as
missing evidence, rather than treated as a reason to buy immediately.

Review history retains previous decisions. Conflicting changes in another
session require reloading the latest version before saving. Linking a purchased
successor retires the original garment while preserving its inventory and wear
history. Add the successor to the ordinary wardrobe first.

## Calculate coverage

Create lifestyle needs for specific garment categories, seasons, activities and
climates. Set a minimum quantity, weekly uses, laundry interval and wears between
washes. The quantity calculation is:

```text
needed = max(minimum quantity,
             ceil(weekly uses * laundry days / (7 * wears between washes)))
```

The audit compares that need with eligible matching garments. It also lists
unreviewed garments, repairs, fit and comfort problems, and replacement decisions.
Review uncertain items before buying replacements. Category coverage measures
garments for a stated role; it does not prove every possible combination is a
comfortable or stylistically compatible outfit.

## Compare exact purchases

Add a specific product and size as a shopping candidate. Record composition,
construction evidence, care instructions, measurements, price and currency,
return policy, colors, style, season and known
suitability. Link it to a lifestyle need or the garment it would replace.

The comparison reports budget compatibility, coverage before and after the
purchase, similar owned garments, possible pairings and evidence still needed.
Recorded material, construction, care and measurement evidence is shown for both
the candidate and the garment it would replace. These observations also inform
outfit suggestions; price and brand do not establish garment quality.
Replacing an already-counted garment does not create an extra garment in the
coverage calculation. Different currencies remain incomparable without an
explicit conversion; missing prices or measurements remain unknown.

Product links open the retailer's page. The server does not download arbitrary
product pages, scrape catalogs, place orders or automatically add a purchase to
the inventory.

## Optional AI drafts

The optional draft uses the text observations entered by the owner and the saved
text-model/provider selection. It does not inspect garment photos. The draft is
separate from the confirmed review until the owner edits and saves the evidence.
Physical inspection remains necessary for fabric feel, hidden construction and
comfort. A model cannot establish longevity or fabric authenticity from an
inventory photo.

Basic reviews, audits and purchase comparisons do not need AI, a cloud account,
or a model download. They use recorded evidence and declared requirements.

## Maintenance and recovery

The extension shares Wardrowbe's database and authentication, with an independent
Alembic version table. The packaged migration command runs upstream migrations
before the planning migrations. Existing Wardrowbe database backups include
planning records. No additional service, secret or external database is needed.

Both package builds exercise the extension: backend checks use a disposable
PostgreSQL database, and frontend checks run interactive React tests before the
production build. The automatic updater applies the complete patch sequence to
a disposable copy in derivation order before changing either source manifest.
Build checks remain necessary because successful patch application alone does
not establish runtime compatibility with a new upstream release.
