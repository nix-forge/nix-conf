# Wardrowbe garment quality and replacement capabilities

Reviewed: 2026-09-27. Scope: Wardrowbe 1.10.1, revision `8f91c82bca7c3684d0cc36f36e9dac62bf382cd2`, selected by the local package source. The upstream repository HEAD returned the same revision during this review.

## Answer

Upstream Wardrowbe can catalog individual garments, suggest combinations, track wear and laundry, and show basic wardrobe statistics. The reviewed upstream revision does not provide a garment quality review, repair-versus-replace workflow, or prioritized shopping plan. The local packages now implement those workflows through the [planning extension](../operations/wardrowbe-planning.md). The upstream findings below explain why application changes were necessary.

## Findings and sources

| Need | Current implementation | Limitation or required change |
| --- | --- | --- |
| Distinguish individual white shirts | Each item has its own images, name, brand, notes, subtype, color, material, style, formality and season. Extra item images are supported. | Accurate label composition, measurements, construction and fit observations need manual entry; structured fields would make them usable for analysis. |
| Generate outfits | Suggestions use garment descriptions, occasion, weather, user preferences, recency, and learned pairing information. | The main item description includes name, subtype, color, pattern, material, formality, style, season and fit. Brand, notes, purchase metadata, AI caption and condition are omitted. |
| Assess wear or damage | Notes can record observations. There is a declared condition field inside AI tags. | The vision prompt does not request condition, and its parser does not populate it. This is dormant plumbing, not a working condition assessment. |
| Decide what needs replacing | Wear and wash histories plus purchase date/price and archiving are represented. | No replacement policy, repair queue, expected garment lifespan or replacement priority was found. Old age or low wear alone does not establish poor quality. |
| Identify wardrobe gaps | Analytics show type and color distributions, most/least/never worn items and outfit acceptance. | Suggestions such as adding bottoms or color variety come from fixed thresholds. They do not measure lifestyle coverage, garment condition, budget or shopping value. |
| Build a shopping plan | No wishlist, candidate purchase comparison or replacement linkage was found in the reviewed source. | Needs a separate shopping workflow with existing-wardrobe compatibility and explicit purchase constraints. |

The item model and update API store brand, notes, purchase date and purchase price. The detail editor visibly supports brand and notes. That storage must not be confused with sending those details to the outfit model. Sources: [item model](https://github.com/Anyesh/wardrowbe/blob/8f91c82bca7c3684d0cc36f36e9dac62bf382cd2/backend/app/models/item.py), [item API schemas](https://github.com/Anyesh/wardrowbe/blob/8f91c82bca7c3684d0cc36f36e9dac62bf382cd2/backend/app/schemas/item.py), [item detail editor](https://github.com/Anyesh/wardrowbe/blob/8f91c82bca7c3684d0cc36f36e9dac62bf382cd2/frontend/components/item-detail-dialog.tsx).

The vision classification prompt requests type/subtype, colors, pattern, broad material, formality, style, season and a broad fit label. The second prompt asks for a caption under 20 words. Neither requests seam construction, fabric composition percentages, damage, pilling, transparency, shrinkage, longevity or repair recommendations. Material is inferred into a small vocabulary; it should be checked against the actual garment label. Sources: [vision analysis prompt](https://github.com/Anyesh/wardrowbe/blob/8f91c82bca7c3684d0cc36f36e9dac62bf382cd2/backend/app/prompts/clothing_analysis.txt), [caption prompt](https://github.com/Anyesh/wardrowbe/blob/8f91c82bca7c3684d0cc36f36e9dac62bf382cd2/backend/app/prompts/clothing_description.txt).

`ClothingTags.condition` exists and the worker stores its value in tags. However, the response parser does not assign condition, brand, occasion or features from the AI response. Its defaults remain empty in the normal tagging flow. The API's editable ItemTags schema also does not expose condition. A visible condition badge in frontend code therefore does not establish automatic condition assessment. Sources: [tag response parser](https://github.com/Anyesh/wardrowbe/blob/8f91c82bca7c3684d0cc36f36e9dac62bf382cd2/backend/app/services/ai_service.py), [tagging worker](https://github.com/Anyesh/wardrowbe/blob/8f91c82bca7c3684d0cc36f36e9dac62bf382cd2/backend/app/workers/tagging.py), [item API schemas](https://github.com/Anyesh/wardrowbe/blob/8f91c82bca7c3684d0cc36f36e9dac62bf382cd2/backend/app/schemas/item.py), [item detail editor](https://github.com/Anyesh/wardrowbe/blob/8f91c82bca7c3684d0cc36f36e9dac62bf382cd2/frontend/components/item-detail-dialog.tsx).

Daily recommendations use text descriptions rather than re-examining the original photos. Their garment formatting omits notes, brand, purchase details, condition and AI description. The per-item pairing formatter is narrower still, using name, type/subtype, color, pattern, material and formality. Sources: [recommendation formatter](https://github.com/Anyesh/wardrowbe/blob/8f91c82bca7c3684d0cc36f36e9dac62bf382cd2/backend/app/services/recommendation_service.py), [pairing formatter](https://github.com/Anyesh/wardrowbe/blob/8f91c82bca7c3684d0cc36f36e9dac62bf382cd2/backend/app/services/pairing_service.py).

Analytics use SQL aggregates and fixed rules. For example, a color over 40% of the wardrobe can prompt adding variety; a tops-to-bottoms ratio above three can prompt adding pants or skirts. These are general balance hints, not a personalized purchasing analysis. They could be inappropriate for a deliberate capsule wardrobe. Source: [analytics implementation](https://github.com/Anyesh/wardrowbe/blob/8f91c82bca7c3684d0cc36f36e9dac62bf382cd2/backend/app/api/analytics.py).

The local AI provider/model patches change request transport, credentials and model selection. Inspection found no added condition, quality, shopping or replacement workflow there. Sources: [backend provider patch](../../pkgs/pkgs/by-name/wa/wardrowbe-backend/ai-providers.patch), [frontend model selection patch](../../pkgs/pkgs/by-name/wa/wardrowbe-frontend/model-selection.patch).

## Recommended changes

Start with a garment review workflow. Store user-confirmed condition, fit problems, fabric composition from labels, measurements, construction observations, care requirements, and repair needs. Keep evidence and the date of review. Treat inferred observations as suggestions requiring confirmation.

Add an explicit availability and review state so an item awaiting repair or replacement does not keep appearing in outfits. Keep usable older garments available. Preserve worn history and archive records when replacing an item, with a link between the old garment and its successor.

A wardrobe audit should compare usable garments against stated occasions, climate, laundry cadence, preferred fit and budget. It should output specific findings such as "this work shirt needs a collar repair" or "one additional opaque summer work shirt would cover laundry days," with the garments and evidence behind each finding. Avoid automatic shopping based on a universal wardrobe ratio.

Shopping candidates should have exact product/model, size, composition, measurements, price, return policy and source URL. Compare them with the existing wardrobe and replacement need. Show which outfits they unlock, duplicates they introduce and unresolved fit or quality questions. This is a proposed feature, not current Wardrowbe behavior.

An AI model can help identify visible features and explain options. Photos alone cannot reliably establish hidden construction, fiber authenticity, tactile quality or durability. Human inspection and labels remain necessary inputs. The University of Georgia's [garment quality and selection guidance](https://site.extension.uga.edu/textiles/quality-and-selection/) describes choosing garments for fit, lifestyle and construction quality.

## Validation and limits

Reviewed source at the package revision and checked upstream HEAD with `git ls-remote`. No runtime garment uploads, model evaluations, shopping tests or physical garment inspections were performed. Claims of absence concern the reviewed open-source implementation and local provider patches, not every possible hosted product or future release. Source review establishes intended data flow, not model accuracy.

The hosted product's marketing may describe broader gap analysis or partner shopping recommendations. Those claims should not be treated as capabilities of this deployed open-source revision without an implemented route, schema and user workflow.

## Local integration design

The planning extension reuses native authentication and database sessions, with
owner predicates for every record and linked garment. It separates confirmed
evidence from unsaved AI drafts, availability from replacement intent, and
category coverage from verified outfit compatibility. Product URLs are stored
without server-side fetching. These choices follow the existing application
contracts and [FastAPI dependency injection](https://fastapi.tiangolo.com/tutorial/dependencies/).

Independent extension tables and an independent Alembic version table avoid
attaching local migration revisions to an upstream release's head. The migration
command upgrades upstream first, then the extension. Alembic supports explicit
[version tables](https://alembic.sqlalchemy.org/en/latest/api/runtime.html#alembic.runtime.environment.EnvironmentContext.configure)
and [programmatic migration commands](https://alembic.sqlalchemy.org/en/latest/cookbook.html#sharing-a-connection-across-one-or-more-programmatic-migration-commands).
The choice of separate migration histories is an implementation decision to
preserve automatic upstream updates, rather than an upstream Wardrowbe feature.

Inputs use bounded schemas, decimal prices, explicit currencies and stale-version
checks. The AI draft releases its database transaction before a provider call;
SQLAlchemy documents that concurrent operations must not share a mutable
[AsyncSession](https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html#using-asyncsession-with-concurrent-tasks).
The server does not fetch candidate URLs, avoiding the additional network trust
boundary described by [OWASP's SSRF guidance](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html).
