# Security Hardening Review: Cashback shopping isolation

## Evidence Basis

This review combines current Rakuten, Mozilla, Apple, Bitwarden, uBlock Origin, and Home Manager documentation with the repository's browser policy and personal extension configuration. The [research note](../browser-shopping-profile-research.md) contains the source-level findings. The working tree is not clean, so the proposal describes the inspected state rather than a deployed revision.

## Constraints

Cashback attribution requires some transaction tracking. We want to keep that tracking out of daily browsing, leave uBlock Origin enabled in the daily context, retain browser security controls during checkout, and avoid a fiddly enable-disable routine. No runtime performance or memory measurements were supplied.

## Opportunity Portfolio

| Opportunity | Evidence | Options | Recommendation | Proposal |
| --- | --- | --- | --- | --- |
| Isolate cashback tracking from daily browsing | Rakuten website and extension terms, Mozilla profile and container behavior, current application-wide Nix policies | Daily exceptions; separate Firefox profile; dedicated shopping browser | Keep Personal and Shopping profiles inside Firefox and use Rakuten.com without the extension | [Full proposal](proposals/isolate-cashback-tracking.md) |

## Recommendation Summary

Keep research in Zen with uBlock Origin enabled, then switch to Firefox's visibly distinct Shopping profile for the final Rakuten click-through and checkout. Rakuten documents the website as a complete alternative to its extension. The profile keeps affiliate cookies and browsing history separate without taking ordinary Firefox use away.

Firefox's application-wide extension policy now permits named daily extensions instead of installing them into every profile. Firefox owns their per-profile installation and updates. Bitwarden remains the only extension installed automatically in Shopping. A container alone does not contain extension permissions.

## Next Decisions

The two-profile Firefox option is implemented. Personal remains the default Firefox profile, Shopping clears transaction state on clean shutdown, and no extra application is installed. The remaining operational validation is a low-value purchase with Firefox Standard tracking protection and no Rakuten extension.
