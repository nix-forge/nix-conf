# Security Hardening Proposal: Isolate cashback tracking from daily browsing

## Decision

Choose where Rakuten-compatible browsing should run and how much of the daily browser it may observe. The practical decision is between per-site exceptions in the daily profile, a separate Firefox profile, and a dedicated supported browser application.

## Executive Recommendation

Option 1, **daily-browser exceptions**, keeps the current browser arrangement and uses a shopping container or ordinary tab. It costs the least to set up, but it shares add-ons and browser policy with daily browsing and requires the ad-blocker exception the user wants to avoid.

Option 2, **separate Firefox profile**, separates site data and add-ons with a good cross-platform user experience. This is the selected option because Firefox must remain useful for ordinary browsing. Nix permits the named daily extensions, Firefox owns their per-profile installation and updates, and only Bitwarden installs automatically in every Firefox profile.

Option 3, **dedicated shopping browser**, has stronger application separation, but it would repurpose Firefox and remove its normal browsing role. The user rejected that tradeoff. Starting at Rakuten.com still makes the Rakuten extension unnecessary.

## Evidence

I inspected the current browser adapters and personal extension configuration, then checked the behavior against the primary-source research in `E001`. The extension's all-site data collection and Rakuten's own website-based purchase path matter most here.

| Evidence | Finding or document | What it establishes |
| --- | --- | --- |
| `E001` | [Shopping-profile primary-source research](../../browser-shopping-profile-research.md) | Rakuten's extension is optional, collects broad browsing data, and is incompatible with the user's desired ad-blocking posture. Mozilla distinguishes full profile separation from container cookie separation. |
| `E002` | [Shared extension schema](../../../modules/home/browsers/shared/extensions.nix) | uBlock Origin is currently required in both managed browsers. |
| `E003` | [Firefox adapter](../../../modules/home/browsers/firefox/default.nix) | Firefox receives one application-wide `ExtensionSettings` policy built from shared and Firefox-specific entries. |
| `E004` | [Zen adapter](../../../modules/home/browsers/zen/default.nix) | Zen has its own application policy and can retain the protected daily-browser extension set. |
| `E005` | [Personal extension membership](../../../homes/shared/local/browsers/extensions.nix) | Personal extension choices already live outside reusable modules and can be regrouped by browser. |

## Current Design And Failure Mode

The current setup treats uBlock Origin as a required shared extension. That is sensible while Firefox and Zen are both general-purpose browsers. It stops being suitable when one context must intentionally permit affiliate attribution that Rakuten says uBlock Origin may block.

Containers do not solve that mismatch. They isolate cookies, logins, and site data, but the same profile still owns its add-ons and policies. If we installed Rakuten in that profile, its all-site permission would not stop at the shopping container. If we kept only the website flow, uBlock Origin would still need exceptions inside the same profile. This gives us organization and cookie separation, but not the extension boundary the user asked for.

The Rakuten extension itself is not required. Rakuten documents a website flow in which the user signs in at Rakuten.com, selects a merchant, follows the generated link, and finishes checkout in the same session. That lets us remove the broad extension capability rather than trying to constrain it after installation.

## Desired Invariants

- Rakuten code cannot observe tabs, URLs, searches, or carts in the daily browsing context.
- uBlock Origin remains enabled without exceptions in the daily browsing context.
- The purchase context retains Safe Browsing, certificate validation, HTTPS-Only Mode, and a deny-by-default extension policy.
- Only the transaction session accepts the affiliate tracking needed for cashback.
- The user can tell the daily and shopping contexts apart before entering credentials or payment data.
- Closing or resetting the shopping context removes its accumulated site data without risking an in-progress checkout.

## Constraints And Non-Goals

The target is a personal workstation, not a hostile-code sandbox. Separate profiles and browsers still run as the same operating-system user and share the device IP address. We are limiting routine tracking and accidental exposure, not defending against a malicious browser binary or compromised operating system.

Cashback attribution necessarily reveals the transaction path to Rakuten and its affiliate network. The proposal cannot both preserve that attribution and eliminate the tracking used to prove it. Compatibility also requires cookies until checkout and order confirmation complete.

## Before Architecture

[Before diagram](../diagrams/isolate-cashback-tracking-before.mmd)

The unsafe version places research, checkout, uBlock Origin exceptions, and a broadly permissioned cashback extension in one daily profile. Even when shopping tabs use a container, the add-on boundary remains the profile.

## Options

### Option 1: Daily-browser exceptions

This option keeps the current browser roles. The user opens a Shopping container or normal tab, starts at Rakuten.com, and temporarily trusts the necessary sites in uBlock Origin. The Rakuten extension remains unnecessary. If installed for reminders, however, it can observe the whole profile and defeats the main containment goal.

The attractive part is its low setup cost. Containers provide a visible color and separate merchant cookies from other containers. The problem is operational: affiliate redirects vary, Rakuten does not guarantee that trusting only its hostname and the final merchant is enough, and the user must remember when to relax and restore filtering. This is precisely the repeated toggle the request is trying to remove.

[Option 1 diagram](../diagrams/isolate-cashback-tracking-daily-browser-exceptions-after.mmd)

| Change | Before | After | Security consequence | Cost |
| --- | --- | --- | --- | --- |
| Shopping state | Ordinary daily tabs | Shopping container | Merchant cookies are separated | Small setup and routing burden |
| Cashback activation | Potential extension | Rakuten.com click-through | Removes Rakuten's all-site extension access | Must start each trip manually |
| Content blocking | Enabled everywhere | Site or session exceptions | Daily profile temporarily accepts more tracking | Error-prone toggling and attribution troubleshooting |

Rollback is trivial: delete the container assignments and remove trusted-site entries. No Nix restructuring is needed. Residual risk remains high enough that I would use this only when adding another profile or browser is unacceptable.

### Option 2: Separate Firefox profile

A Firefox `Shopping` profile gives us separate add-ons, cookies, history, settings, and visible profile identity while preserving a single Firefox application. The profile would use Standard tracking protection, keep Safe Browsing and HTTPS protections, omit uBlock Origin, and start purchases at Rakuten.com. Its extension list should contain only Bitwarden unless real use demonstrates a need for Rakuten's extension.

This is a sound browser-level privacy boundary. Firefox enterprise policies apply to the application, so the implementation adds an `allowed` mode for profile-local installation. The wildcard still rejects undeclared extensions. Firefox owns installation state and updates inside each profile, while Nix defines which extension IDs are permitted. Home Manager's profile package mechanism was rejected because it would move extension versions and updates into Nix.

[Option 2 diagram](../diagrams/isolate-cashback-tracking-separate-profile-after.mmd)

| Change | Before | After | Security consequence | Cost |
| --- | --- | --- | --- | --- |
| Data boundary | One Firefox profile | Daily and Shopping profiles | Separates history, cookies, logins, and add-ons | Profile launcher and lifecycle management |
| Policy ownership | Application installs every allowed extension | Policy permits profile-specific membership | Rakuten can remain absent from daily profile | Extension module redesign and mixed declarative/runtime state |
| uBlock Origin | Required application-wide | Present only in daily profile | Shopping can function without weakening daily filtering | Browser-update or Nix-pinning tradeoff |

This option can roll back by removing the Shopping profile and reverting the policy-mode change. The ownership rule is explicit: Nix controls the allowlist, Firefox controls whether an allowed daily extension is installed in a particular profile and keeps it updated.

### Option 3: Dedicated shopping browser

This option assigns browser roles instead of asking one application's policy to vary by profile. Zen remains the daily research browser with uBlock Origin and Strict tracking protection. A supported browser, preferably the already installed Firefox on this repository's macOS host, becomes the shopping browser. Firefox gets a minimal extension set, a distinct name or launcher, Standard tracking protection, and a Rakuten.com start page. It is never the default browser.

No Rakuten extension is needed. The user researches in Zen, copies the final product reference, opens the shopping browser, starts a fresh trip at Rakuten.com, and completes checkout in the opened merchant tab. Bitwarden is the only justified extension. Firefox clears shopping cookies, site data, cache, sessions, and history on a clean shutdown; crash recovery remains available until Firefox exits normally.

This option fits the existing configuration because Firefox and Zen already have separate adapters and extension groups. We can move uBlock Origin and research extensions into Zen's group while leaving only Bitwarden in Firefox. Browser-managed AMO updates continue to work. The main cost is that Firefox stops being a second general-purpose daily browser. If that role matters, a separately packaged supported browser or a Safari Shopping profile becomes preferable.

[Option 3 diagram](../diagrams/isolate-cashback-tracking-dedicated-browser-after.mmd)

| Change | Before | After | Security consequence | Cost |
| --- | --- | --- | --- | --- |
| Browser role | Firefox and Zen are general purpose | Zen researches; Firefox purchases | Rakuten-compatible state cannot observe Zen data or add-ons | Firefox is no longer a normal fallback browser |
| Extension set | Shared uBlock Origin and workflow tools | Zen keeps blockers; Firefox keeps Bitwarden | Daily protection stays enabled and shopping has minimal code | Personal extensions must be regrouped |
| Cashback path | Extension or ad-blocker toggles | Rakuten.com click-through | Removes broad Rakuten extension access | One deliberate browser switch per purchase |
| Shopping data | Retained with ordinary browsing | Separate browser data cleared on clean shutdown | Limits long-term affiliate state | Merchant sign-in is intentionally temporary |

Rollback is clean because the browser adapters remain separate. Restoring Firefox as general purpose means moving extensions back to `shared` or `firefox` and removing the shopping-specific launcher and settings.

## Comparison

| Dimension | Option 1: Daily exceptions | Option 2: Separate profile | Option 3: Dedicated browser |
| --- | --- | --- | --- |
| Security | Cookie isolation only; filtering weakened in daily profile | Strong profile data and add-on isolation after policy redesign | Strong application data and policy separation; no Rakuten extension |
| Performance | No meaningful added runtime cost | One additional browser instance when concurrent | One additional browser process when concurrent |
| Memory | Container tabs share the existing browser | Concurrent profiles add a browser instance | Concurrent browsers add a browser instance |
| Reliability | Affiliate-domain exceptions may miss redirects | Reliable after extension ownership is resolved | Closest to Rakuten's supported-browser website flow |
| Operability | Repeated toggles and troubleshooting | Profile launcher plus policy-state ownership | Clear launcher, browser role, and reset action |
| Migration | Minimal | Moderate module redesign | Small regrouping of browser-specific settings |

These effects are source-derived or hypothetical, not measured. Before implementation we should record idle memory with both contexts open and run a low-value test purchase. The decision threshold is practical: if the extra browser remains responsive and Rakuten records the trip without a blocker exception or extension, the dedicated-browser cost is acceptable.

## Recommendation

The user clarified that Firefox must remain a general-purpose browser, so Option 2 is the right choice. Personal remains Firefox's default profile with Strict tracking protection and the approved daily extensions. Shopping has Standard tracking protection, Bitwarden, an orange accent, and automatic cleanup on a normal exit. Firefox's built-in profile switcher replaces a separate launcher.

Option 1 remains reasonable only if profile switching is unacceptable. It cannot isolate extension permissions and would require uBlock exceptions during purchases. Option 3 is stronger isolation but takes away a browser role the user wants to keep.

## Evidence Coverage And Residual Risk

| Evidence | Option 1 | Option 2 | Option 3 |
| --- | --- | --- | --- |
| `E001` — Rakuten and isolation research | Mitigates extension tracking only if the extension is omitted | Addresses daily-data exposure | Addresses daily-data exposure and uses documented website flow |
| `E002` — Shared forced uBlock Origin | Unaffected; exceptions still required | Requires redesign | Addressed by moving uBlock Origin to Zen |
| `E003` — Firefox application policy | Unaffected | Requires a new profile-aware ownership model | Reused as the shopping-browser policy |
| `E004` — Zen application policy | Reused unchanged | Reused unchanged | Reused as the protected daily policy |
| `E005` — Personal extension membership | Small container-specific additions | Requires per-profile declarations | Requires regrouping by browser role |

All options leave Rakuten and the merchant able to associate the purchase with the user's account, IP address, device characteristics, and payment details. A separate browser is not a sandbox against malicious native code. The dedicated-browser option also depends on disciplined use: ordinary links should continue opening in Zen, and the shopping browser should remain closed outside purchase sessions.

## Migration And Rollout

The user selected a separate Firefox Shopping profile and kept the existing Personal profile as Firefox's default. The implementation removes the extra launcher, keeps app-wide policies suitable for normal browsing, and applies cleanup only through Shopping profile preferences. The remaining rollout step is a low-value eligible purchase through Rakuten.com.

Rollback preserves receipts and profile data. Disable the Shopping profile module and restore automatic Firefox extension modes if per-profile installation is no longer wanted. Do not delete either profile automatically.

## Validation Plan

- Confirm Firefox's `about:policies` shows only the intended allowlisted extensions and no Rakuten extension.
- Confirm Zen keeps uBlock Origin active and has no Rakuten access.
- Verify an ordinary HTTP or HTTPS link opens Zen, not the shopping browser.
- Start a Rakuten shopping trip from Rakuten.com and confirm the merchant opens in the same transaction window.
- Use a low-value eligible purchase to verify that the trip and cashback appear.
- Close Firefox normally and confirm shopping cookies, history, cache, and site storage are removed while downloaded receipts remain.
- Measure idle memory for Zen alone and Zen plus the shopping browser. Record the result rather than assigning a speculative budget now.
- Force-quit the shopping browser during a test session and confirm crash recovery remains available; then close normally and confirm state is cleared.

## Implementation Work Packages

- Add a Shopping profile inside the existing Firefox application.
- Permit approved daily extensions without automatically installing them into Shopping.
- Keep app-wide policies safe for Personal and put Standard tracking protection and cleanup preferences only in Shopping.
- Use Firefox's built-in profile switcher and a profile-specific orange accent instead of another application.
- Extend the browser configuration contract to check profile ownership, extension modes, and cleanup scope.

These work packages were authorized and implemented on 2026-09-02. The implementation handoff records the exact module and validation choices.

## Open Question

- Does a low-value test purchase succeed with Firefox Standard tracking protection and no Rakuten extension?
