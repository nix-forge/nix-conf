# Wardrobe software research

Reviewed: 2026-09-24. Scope: personal clothing inventory, outfit creation, color guidance, and weekly planning, with preference for open source and Linux self-hosting.

## Answer

GetWardrobe is the most complete documented product for this combination of needs. It offers photo import with category and color detection, color and style compatibility suggestions, manual and AI outfit creation, a future outfit calendar, weather matching, a Linux-compatible web app, and ZIP export containing CSV data and images. It is a hosted proprietary service. Its free plan allows up to 100 items and outfits; US Premium is $9.99 monthly or $49.99 yearly. Advanced AI models and virtual try-on use separate credits. See its [feature list](https://help.getwardrobe.com/latest/features/), [combination guide](https://help.getwardrobe.com/latest/items/explore-combinations/), [planning guide](https://help.getwardrobe.com/latest/outfits/planning/), [Linux web app guide](https://help.getwardrobe.com/latest/settings/use-on-computer/), [data archive guide](https://help.getwardrobe.com/latest/settings/app-settings/), and [pricing](https://getwardrobe.com/pricing/).

Libre Closet is the best documented open-source and self-hosted match when a visual weekly outfit schedule matters. Its AGPL-3.0 project provides a clothing catalog with colors, saved outfits, outfit scheduling across the week, photo background removal, an offline-capable PWA, and a Docker deployment using SQLite and local image storage by default. Release v0.5.0 added garment color-combination support; v0.5.1 was published in September 2026. Its documentation does not establish personalized palette analysis or automated weather-aware styling. See the [README](https://github.com/Lazztech/Libre-Closet/blob/main/README.md), [license](https://github.com/Lazztech/Libre-Closet/blob/main/LICENSE), and [releases](https://github.com/Lazztech/Libre-Closet/tags).

## Other credible choices

| Product | Relevant strengths | Decision-relevant limit |
| --- | --- | --- |
| [Wardrowbe](https://github.com/Anyesh/wardrowbe) | MIT licensed self-hosted app with AI garment tagging, weather and occasion outfit recommendations, wear feedback, color distribution, notifications, and support for local Ollama models. | Its documented calendar shows wear history. No future week planner was verified. Local AI adds memory and model requirements. |
| [Whering](https://www.whering.co/) | Hosted wardrobe, outfit creation and planning, shuffle ideas, packing, analytics, and social styling. | Proprietary hosted product; it does not satisfy self-hosting. Its focus on social styling is a preference question. |
| [Acloset](https://www.acloset.app/) | Hosted AI recommendations based on schedule, weather, mood, and personal colors, plus virtual try-on. | Its documented desktop offering is a Chrome extension, not a full Linux web planner. |
| [Indyx](https://www.myindyx.com/) | Free unlimited catalog, outfit creation, calendar tracking, packing, and optional human stylist. | Its first-party materials emphasize human styling rather than automatic color-pairing recommendations. [A CSV export requires a support request and fee](https://www.myindyx.com/contact-us). |
| [Stylebook](https://stylebookapp.com/features.html) | Mature outfit editor, future calendar, packing, color statistics, and wear statistics with a one-time price. | [iPhone and iPad only](https://www.stylebookapp.com/faq.html), so unsuitable for a Linux-centered workflow. |
| [Cladwell](https://cladwell.com/app) | Capsule-wardrobe templates, daily weather and activity recommendations, planning, and AI style questions. | Hosted subscription product; less directly suited to Linux home-lab ownership. |

## Validation and limits

Findings come from official product documentation and source repositories retrieved on 2026-09-24. No application was installed or used in this review. Vendor descriptions establish available controls, not recommendation quality or background-removal accuracy. Libre Closet and Wardrowbe are younger projects than the established hosted products, so a small trial with a subset of garments is warranted before entering an entire wardrobe. GetWardrobe's archive cannot be imported back into GetWardrobe according to its [settings guide](https://help.getwardrobe.com/latest/settings/app-settings/); it is a backup and portability format, not full restore.

## Implication for this repository

No configuration change is recommended from research alone. If deployed later, Libre Closet is the first self-hosted candidate to trial. GetWardrobe is the first hosted candidate to trial for overall function quality.
