# Firefox and Zen Browser configuration research

## Implementation status

The migration described in this review is implemented. Firefox and Zen now use one browser-suite interface, small shared data builders, thin browser adapters, and host-local personal configuration. The old preset stacks, duplicate search and extension modules, duplicated scrolling files, obsolete Zen package override, invalid Zen language-pack request, and unused Firefox inputs are gone.

The resulting profiles keep strict tracking protection, Safe Browsing, OCSP, HTTPS-Only Mode, uBlock Origin, Bitwarden, useful browsing features, and automatic graphics defaults without the conflicting multi-thousand-line `user.js` layers. Zen uses its signed beta package on Darwin; Firefox uses Mozilla's signed binary package there. A dedicated flake check covers the cross-browser contract independently of the larger desktop contract.

Extensions are grouped as shared, Firefox-only, or Zen-only. Each entry uses a `normal` or `required` mode. A shared function compiles each browser's effective extension set into an allowlist, so active AMO extensions update in the browser and removing an entry also removes that profile-installed extension. No retired-extension list is needed.

The findings below describe the pre-migration state and explain the decisions embodied in the current configuration.

## Review conclusion

Firefox and Zen should share configuration data, not duplicate whole modules. The pinned Zen Home Manager module is built on Home Manager's Firefox module, so both browsers can consume the same policies, extension catalog, search engines, native messaging hosts, language packs, profile preferences, bookmarks, containers, handlers, and profile CSS. Zen's spaces, pins, essentials, routes, shortcuts, mods, and other Zen state should remain in a Zen-specific module. [Zen imports `mkFirefoxModule` directly](https://github.com/0xc000022070/zen-browser-flake/blob/382e4f584c03b750d35849faff70ac1aa44fd6cf/hm-module/default.nix#L43-L77), and the [pinned Home Manager implementation defines the shared interface](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/programs/firefox/mkFirefoxModule.nix#L224-L905).

The highest-priority change is to remove the stacked Arkenfox, Securefox, Peskyfox, Fastfox, and BetterZen preference files. They make ownership and precedence hard to audit, apply Firefox-specific assumptions to Zen, and then disable important parts of the hardening in a final override. Replace that stack with a small, explicit shared baseline. If a preset is retained, use only one and add deliberate compatibility and security overrides.

The immediate correctness problems are more serious than duplication alone. On the evaluated macOS target, both browsers write `EnterprisePoliciesEnabled = false`, which overrides Home Manager's injected `true` and prevents their enterprise policies from being enabled. Zen's generated en-US language-pack URL also returns 404 because Home Manager uses Zen's `1.22t` package version as if it were a Firefox release. The next priorities are to fix Firefox's obsolete `searchUrl` search-engine definitions, remove the obsolete Zen macOS package override, unify extension and uBlock configuration, and move personal search, UI, extension, and resolver decisions into each host's `local` directory.

## Scope and source baseline

This review covers:

- `modules/home/firefox/`
- `modules/home/zen-browser/`
- `modules/shared/browser-policies.nix`
- `homes/macbook-pro-m4/local/firefox.nix`
- `homes/macbook-pro-m4/local/zen-browser.nix`
- the browser-related Stylix modules, flake inputs, and helper library

The repository currently pins Home Manager at `99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11` and Zen Browser Flake at `382e4f584c03b750d35849faff70ac1aa44fd6cf`. Conclusions about module behavior below refer to those revisions, not an assumed latest release.

## What can be shared

The two program option namespaces differ, but their values can be built from the same attrsets and lists.

| Concern | Share? | Recommended owner |
| --- | --- | --- |
| Enterprise policies | Yes | `modules/home/browsers/shared/policies.nix` |
| Extension definitions | Yes | `modules/home/browsers/shared/extensions.nix` |
| uBlock settings | Mostly | Shared conservative baseline; personal rules in `homes/*/local` |
| Search-engine definitions | Yes | Shared neutral engines; personal engines and defaults in `homes/*/local` |
| Language packs | Yes | Shared profile data |
| Profile preferences | Yes | Shared audited settings plus small browser-specific overlays |
| Native messaging hosts | Yes | Shared package list, enabled only when an extension requires it |
| Bookmarks, containers, handlers, CSS | Structurally yes | Shared only when genuinely common; personal content remains local |
| Scrolling preferences | Yes | One selected shared preset |
| Hardware overrides | Usually no | Host-local because GPU, compositor, and operating system matter |
| Zen spaces, pins, essentials, routes, shortcuts, mods | No | Zen-specific and usually personal/local |
| Default-browser integration | Partly | Shared intent, platform-specific implementation |

The current extension, language, policy, scrolling, search, and user-preference modules are mostly pairs that differ only in `programs.firefox` versus `programs.zen-browser`. A shared module should expose plain values or helper functions and assign those values under each program. This is clearer than dynamically constructing option paths.

## Current correctness and maintenance problems

### Preference precedence is backwards for structured settings

Both `modules/home/firefox/user-js.nix` and `modules/home/zen-browser/user-js.nix` put large raw files in `profiles.default.extraConfig`. Home Manager writes structured `profiles.<name>.settings` before `extraConfig`, so a preference in the raw tail can override a structured setting unexpectedly. Home Manager provides `preConfig` for raw content that must precede structured settings. The ordering is visible in the [pinned `mkFirefoxModule` implementation](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/programs/firefox/mkFirefoxModule.nix).

The local stack contains hundreds of assignments and many repeated keys. The rendered Firefox `user.js` contains 71 preference keys assigned more than once; Zen contains 105. Nine final local overrides conflict with values assigned earlier in the generated files. These counts are from the evaluated target, so they include the actual concatenation and Home Manager output rather than only a source-text estimate. Firefox loads Arkenfox plus three Betterfox guide files. Zen adds BetterZen on top. Betterfox presents its root `user.js` as the curated configuration while Securefox, Peskyfox, Smoothfox, and Fastfox are documented component guides. [Betterfox documents that distinction in its repository](https://github.com/yokoffing/Betterfox). Arkenfox also states that its project is specifically for desktop Firefox and warns that using it unchanged in Gecko forks can be counterproductive. [Arkenfox documents the fork warning in its README](https://github.com/arkenfox/user.js#readme).

Recommendation:

1. Prefer a small explicit `settings` attrset and policies whose effects can be reviewed in this repository.
2. If a preset remains, choose one. Do not combine Arkenfox and every Betterfox component.
3. For Zen, prefer its structured `profiles.default.presets.betterfox.enable` implementation if Betterfox is desired. It applies preferences with `mkDefault`, permits explicit settings to win, and removes stale managed preferences when disabled. [The preset parser](https://github.com/0xc000022070/zen-browser-flake/blob/382e4f584c03b750d35849faff70ac1aa44fd6cf/hm-module/lib/user-js-preset.nix) and [cleanup module](https://github.com/0xc000022070/zen-browser-flake/blob/382e4f584c03b750d35849faff70ac1aa44fd6cf/hm-module/presets/cleanup.nix) implement those semantics.
4. If Firefox must retain a raw file, put it in `preConfig` and keep final structured overrides in `settings`.

Mozilla recommends managing a preference through one mechanism rather than setting the same preference through both enterprise policy and preference configuration. [Mozilla's Preferences policy documentation explains the supported policy mechanism](https://mozilla.github.io/policy-templates/#preferences). The current stack manages telemetry, search, new-tab, profile, and privacy behavior in several layers, so it should be simplified before adding more preferences.

### Firefox search contains invalid legacy fields

`modules/home/firefox/search.nix` defines Google AI Mode and Perplexity with `searchUrl`. The pinned Home Manager interface expects `urls = [{ template; params; }]`; its migration code does not translate `searchUrl`. [The current search module defines and serializes the accepted shape](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/programs/firefox/profiles/search.nix#L429-L527). Evaluation confirms that the Firefox search artifact contains the unknown unprefixed `searchUrl` key rather than Firefox's current `_urls` representation. The Zen copies already use the current `urls` form.

Build one shared engine attrset using `urls`. Put neutral developer engines such as Nix Packages, the NixOS Wiki, Noogle, and GitHub in shared configuration. Put Google AI Mode, Perplexity, ChatGPT, YouTube, Cornell, and the chosen normal/private defaults in local configuration because they describe the user's services and workflow.

Both search modules set `force = true`. Home Manager documents this as replacing the browser's search configuration, which is appropriate for fully declarative ownership but prevents durable GUI-added engines. [The pinned search option implementation describes the force behavior](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/programs/firefox/profiles/search.nix). Keep it only if that tradeoff is intended.

### The Zen macOS package override is obsolete

`modules/home/zen-browser/default.nix` removes a `codesign` fragment from the package install phase. That fragment is not present in the pinned Zen package implementation, so the replacement is now a no-op. Remove the custom `unwrappedPackage` override and use the module default.

The pinned Zen module defaults to signed package mode on Darwin. Its documentation says signed mode preserves the upstream app signature and supports Gatekeeper, Touch ID, iCloud Passwords, and native password-manager integration, while wrapped mode loses the signature and those integrations. [The pinned package-mode implementation documents the tradeoff](https://github.com/0xc000022070/zen-browser-flake/blob/382e4f584c03b750d35849faff70ac1aa44fd6cf/hm-module/package.nix#L1-L129).

The custom macOS LaunchServices helper should remain. Zen's `setAsDefaultBrowser` implementation only writes XDG MIME associations and `BROWSER`; it does not manage macOS LaunchServices. [The pinned default-browser module shows those Linux/XDG operations](https://github.com/0xc000022070/zen-browser-flake/blob/382e4f584c03b750d35849faff70ac1aa44fd6cf/hm-module/default-browser.nix).

### Darwin policy activation is currently disabled

`modules/shared/browser-policies.nix` computes `EnterprisePoliciesEnabled` from whether `pkgs` is available and Darwin is detected. On the evaluated macOS Home Manager target, that expression produces `false` for both `org.mozilla.firefox.plist` and `app.zen-browser.zen`.

This value is not a harmless redundant policy. Home Manager constructs Darwin defaults as `{ EnterprisePoliciesEnabled = true; } // cfg.policies`, so the explicit value in `cfg.policies` wins. [The pinned module shows this merge order](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/programs/firefox/mkFirefoxModule.nix#L1219-L1225). The current evaluated output therefore switches enterprise-policy support off after Home Manager enables it, preventing the intended policy set from taking effect on macOS.

Remove `EnterprisePoliciesEnabled` from the shared policy attrset entirely. Let Home Manager own it on Darwin. Verify the generated defaults for both application domains and inspect `about:policies` in both browsers after activation.

### Language-pack URL is broken for Zen

Each browser's `default.nix` and `language.nix` sets `enable` and `languagePacks = [ "en-US" ]`. Apart from being redundant, the inherited Firefox language-pack mechanism is not valid for the pinned Zen package version.

Home Manager builds the language-pack URL from `cfg.release`, which is derived from the package's version, and uses the Firefox release archive path. [The pinned implementation constructs that URL](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/programs/firefox/mkFirefoxModule.nix#L1328-L1340). For Zen Twilight 1.22t, the evaluated policy points to `https://releases.mozilla.org/pub/firefox/releases/1.22t/linux-x86_64/xpi/en-US.xpi`, and that URL [returns 404](https://releases.mozilla.org/pub/firefox/releases/1.22t/linux-x86_64/xpi/en-US.xpi). This leaves Zen's requested language pack uninstalled.

For an en-US-only setup, remove Zen's `languagePacks` entry and rely on the bundled locale. If extra locales are later needed, the Zen module needs a Firefox-version-aware language-pack source rather than `1.22t`. Firefox can retain a shared `[ "en-US" ]` only if explicit installation is useful; otherwise its bundled locale is enough too.

### Unused input

Each browser's `default.nix` and `language.nix` sets `enable` and `languagePacks = [ "en-US" ]`. Let one shared definition own language packs and remove the redundant browser-local assignment.

The direct `firefox-ui-fix` flake input is declared but is not referenced by the browser modules or other repository files. Remove it unless a planned UI module will consume it. Keeping an unused input increases lock-file and update work without configuring either browser.

## Security and compatibility baseline

### Tracking and fingerprinting protection

The final overrides set all of the following:

```nix
"privacy.resistFingerprinting" = false;
"browser.contentblocking.category" = "custom";
"privacy.fingerprintingProtection" = false;
```

Disabling Resist Fingerprinting is reasonable for a compatibility-oriented daily browser. Mozilla documents that RFP can affect site behavior, window and rendering behavior, locale and time zone, input devices, and performance. [Mozilla's RFP support article lists those effects](https://support.mozilla.org/en-US/kb/resist-fingerprinting).

Disabling Firefox's fingerprinting protection as well is too broad for the requested security goal. Prefer Enhanced Tracking Protection Strict with compatibility exceptions, using the `EnableTrackingProtection` enterprise policy where possible. Mozilla describes Strict mode as stronger blocking that can break some sites and provides per-site recovery through the shield panel. [Mozilla documents Standard, Strict, and Custom ETP behavior](https://support.mozilla.org/en-US/kb/enhanced-tracking-protection-firefox-desktop). The enterprise policy supports `Category = "strict"`, `BaselineExceptions`, and `ConvenienceExceptions`. [The policy reference defines those fields](https://mozilla.github.io/policy-templates/#enabletrackingprotection).

Recommended baseline:

```nix
EnableTrackingProtection = {
  Value = true;
  Locked = false;
  Category = "strict";
  BaselineExceptions = true;
  ConvenienceExceptions = true;
};
```

Leave the policy unlocked so a user can recover a broken site. Remove the blanket `privacy.fingerprintingProtection = false` override. Keep RFP off unless a separate hardened profile is introduced.

### Safe Browsing and certificate checks

Betterfox and BetterZen require careful review before use as a security baseline. The preset disables remote download checks and changes Online Certificate Status Protocol behavior. Firefox's default source enables remote Safe Browsing download checks, and Mozilla describes those checks as protection against deceptive sites, malware, unwanted software, and dangerous downloads. [Mozilla documents Firefox's deceptive-content and download protection](https://support.mozilla.org/en-US/kb/block-deceptive-content-and-dangerous-downloads-firefox). Zen's own security page says it uses Google Safe Browsing and certificate validation. [Zen documents its security features](https://docs.zen-browser.app/security).

If a Betterfox-derived preset remains, explicitly restore at least:

```nix
"browser.safebrowsing.downloads.remote.enabled" = true;
"security.OCSP.enabled" = 1;
```

This is another reason to prefer a small reviewed baseline over importing a tuning bundle wholesale.

### HTTPS behavior

`HttpsOnlyMode = "force_enabled"` locks HTTPS-Only Mode on. This is secure but leaves no policy-level escape hatch for a legitimate HTTP-only device or local service. Use `"enabled"` for a compatibility-first daily profile so HTTPS-Only remains on but can be disabled temporarily. The [Mozilla policy reference distinguishes enabled from force-enabled behavior](https://mozilla.github.io/policy-templates/#httpsonlymode). Modern Firefox also uses HTTPS-First upgrades for addresses typed without a scheme, with an HTTP fallback after a failed secure connection. [Mozilla documents HTTPS-First behavior](https://support.mozilla.org/en-US/kb/https-first).

### DNS over HTTPS belongs to the host

The shared policy locks DNS over HTTPS off. That is coherent on the NixOS desktop because the host deliberately owns DNS through Blocky and Unbound. The same policy reaches Darwin, where this repository does not show an equivalent managed resolver.

Move `DNSOverHTTPS` to each host's local browser configuration. Mozilla's default DoH behavior accounts for VPNs, parental controls, enterprise policy, and local network conditions; the maximum-protection mode can make local names unavailable. [Mozilla documents the modes and fallback behavior](https://support.mozilla.org/en-US/kb/dns-over-https). A locked browser policy should therefore reflect a known host resolver, not a universal browser default.

### Firefox accounts and Sync are a personal threat-model choice

`DisableFirefoxAccounts = true` removes Sync, cross-device tabs, bookmarks, passwords, and related account features. Firefox Sync encrypts data before it leaves the browser and Mozilla states that it cannot read the synced data. [Mozilla documents Sync's encryption model](https://support.mozilla.org/en-US/kb/sync). Zen supports Firefox Sync, although Zen-specific browser state is not necessarily portable to Firefox. [Zen documents Sync support and limitations in its FAQ](https://docs.zen-browser.app/faq?pubDate=20250213).

This setting should be local. Keep it disabled if account minimization is the intended threat model. Enable it if feature richness and cross-device UX are more important. The same ownership rule applies to `DisableProfileImport`, `DisableFormHistory`, and `browser.profiles.enabled = false`.

If the new Firefox profile UI is re-enabled, use Home Manager's stable `storeId` field so declarative profiles map predictably to Firefox's profile store. [The pinned Home Manager module exposes `storeId` for this purpose](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/programs/firefox/mkFirefoxModule.nix).

### Policy cleanup

The following entries in `modules/shared/browser-policies.nix` should be removed or reconsidered:

- `DisablePocket` is deprecated in the Mozilla policy schema. [Mozilla marks the policy deprecated](https://mozilla.github.io/policy-templates/#disablepocket).
- `DisableDeveloperTools = false`, `DisableProfileRefresh = false`, `DisablePrivateBrowsing = false`, and `DisableFirefoxScreenshots = false` are no-op declarations unless they intentionally counter another policy layer.
- `PasswordManagerEnabled = false` already disables Firefox's password manager. `DisableMasterPasswordCreation` and `DisablePasswordReveal` add little while it is disabled.
- `AppAutoUpdate = false` plus `ManualAppUpdateOnly = true` expresses two overlapping update strategies. The browser package is owned by Nix, so choose one clear policy. Mozilla documents `ManualAppUpdateOnly` as preserving manual updates, while `DisableAppUpdate` disables application updates. [Mozilla's policy reference defines both update controls](https://mozilla.github.io/policy-templates/).
- `DisableFeedbackCommands = true` also removes the Report Deceptive Site command, which has a security and supportability cost. [Mozilla's policy reference lists the commands affected](https://mozilla.github.io/policy-templates/#disablefeedbackcommands).
- `EnterprisePoliciesEnabled` must be absent from `cfg.policies`, not set from a shared platform check. As described above, the current evaluated `false` value overrides Home Manager's Darwin activation and disables the entire intended policy surface.
- `SearchSuggestEnabled = false` and `FirefoxSuggest.WebSuggestions = false` overlap. Keep a single deliberate privacy decision rather than several controls with similar effects.

Keep `DisableTelemetry`, `DisableFirefoxStudies`, sponsored-content controls, address and credit-card autofill controls, and the Nix-owned update decision in the shared baseline if those match the repository's privacy goals. Keep the built-in password manager disabled only when Bitwarden is guaranteed to be present.

## Extensions and content blocking

### Share one extension catalog

`modules/home/firefox/extensions.nix` and `modules/home/zen-browser/extensions.nix` are exact policy duplicates apart from the program namespace. Define the extension policy attrset once and assign it to both browsers.

### Use the catalog as an extension allowlist

There is no need to keep a list of retired extensions in order to remove them. Set the default `"*"` entry to `installation_mode = "blocked"`, then emit an explicit `normal_installed` or `force_installed` entry for every extension in that browser's effective catalog. Mozilla states that the wildcard applies only when an extension has no specific entry, and that a blocked wildcard removes already-installed extensions that lack an override. Its interaction guidance recommends this exact pattern for blocking everything except a declared set. [Mozilla documents the wildcard and per-ID override behavior in `ExtensionSettings`](https://firefox-admin-docs.mozilla.org/reference/policies/extensionsettings/#interaction-notes).

The wildcard cleanup applies to profile-installed add-ons. Firefox's implementation skips built-in add-ons, system add-ons, and add-ons outside the profile scope, so it does not delete components shipped with or managed outside the profile. [The Firefox policy implementation contains those exclusions](https://searchfox.org/firefox-main/source/browser/components/enterprisepolicies/Policies.sys.mjs#4182-4205). System add-on updates have their own [`DisableSystemAddonUpdate` policy](https://firefox-admin-docs.mozilla.org/reference/policies/disablesystemaddonupdate/) and should not be coupled to this allowlist.

For catalog entries installed from AMO, use its `latest.xpi` URL and keep `updates_disabled = false`. Firefox checks the XPI's internal version and installs, updates, or reinstalls it when that version changes. Mozilla also notes that, as of Firefox 152, `false` keeps automatic updates enabled and prevents the user from turning them off. [Mozilla documents `install_url` and `updates_disabled`](https://firefox-admin-docs.mozilla.org/reference/policies/extensionsettings/#values). This preserves browser-managed extension updates while Nix controls membership in each browser's allowlist.

`normal_installed` guarantees installation but still lets the user disable the extension; use `force_installed` when it must remain active. The wildcard covers profile-scoped themes, dictionaries, locales, and site-permission add-ons as well as ordinary extensions. Mozilla documents Firefox rather than Zen, so applying this behavior to Zen is an inference. Check `about:policies` and the Zen profile after activation.

Remove Query AMO Addon ID. Firefox already exposes extension IDs in `about:support`, and Mozilla's extension policy documentation points administrators there when an ID is needed. [Mozilla documents extension-ID discovery in its policy guidance](https://mozilla.github.io/policy-templates/#extensionsettings). The extra extension broadens the installed code and permission surface without providing a continuing configuration benefit.

The repeated `temporarily_allow_weak_signatures = false` fields are safe but unnecessary unless a parent policy could set them true. Removing them makes the actual extension decisions easier to see.

Use installation modes deliberately. Mozilla's policy reference states that users cannot disable or remove `force_installed` extensions, while `normal_installed` extensions can be disabled. [Mozilla documents `ExtensionSettings` installation modes](https://mozilla.github.io/policy-templates/#extensionsettings). A reasonable split is:

- Keep uBlock Origin forced as the shared security baseline.
- Make Bitwarden forced only while the built-in password manager is disabled.
- Make SponsorBlock, Karakeep, Refined GitHub, Adaptive Tab Bar Colour, and Simplify Jobs normal or local because they are workflow and UI choices.
- Decide explicitly whether Bitwarden should have private-window access. Only uBlock currently receives `private_browsing = true`.

`install_url` values ending in AMO `latest.xpi` allow runtime updates, which is good for rapid extension security fixes but is not bit-for-bit pinned by the Nix lock file. Home Manager also supports package-backed profile extensions and can force its package list, but its module notes that preserving browser extension state matters for first-run enablement. [The pinned Home Manager extension options describe package installation and force behavior](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/programs/firefox/mkFirefoxModule.nix). Choose either timely policy-managed AMO updates or Nix-pinned artifacts consciously rather than mixing models accidentally.

Firefox Stylix installs Firefox Color, while the shared extension policy installs Adaptive Tab Bar Colour. Adaptive Tab Bar Colour's maintainer says it is incompatible with add-ons that modify the Firefox theme. [Its official AMO listing documents the incompatibility](https://addons.mozilla.org/firefox/addon/adaptive-tab-bar-colour/). Remove Adaptive Tab Bar Colour from Firefox, or disable Firefox Color there. Zen may still use the adaptive-color extension if its theme stack is compatible.

### Reduce the uBlock list and rule surface

Firefox has a private 17-list set in `modules/home/firefox/blocking.nix`, while Zen consumes the 7-list set from `modules/shared/browser-policies.nix`. Use one shared, conservative list for both.

uBlock Origin's maintainer warns that more filter lists increase the chance of site breakage and interference and recommends the stock optimized lists for most users. [The official uBlock Origin filter-list documentation explains the tradeoff](https://github.com/gorhill/uBlock/wiki/Dashboard:-Filter-lists). Start with uBlock's defaults and add a short list only when it addresses a known gap.

The `toPairList` helpers preserve Nix booleans, integers, and arrays as JSON values. uBlock Origin's managed-storage schema defines both `userSettings` and `advancedSettings` as pairs of strings, so values such as `true`, `37`, and the `importedLists` array do not match the supported shape. [The authoritative managed-storage schema specifies the string tuple format](https://github.com/gorhill/uBlock/blob/master/platform/common/managed_storage.json). Serialize each value to the string syntax that uBlock expects, or use the documented object fields where an object is supported. Verify the result in uBlock's dashboard because an accepted browser policy is not proof that the extension consumed every field.

`filterAuthorMode` and `updateAssetBypassBrowserCache` are maintainer and debugging controls, not useful daily-browser hardening. Remove both from the common baseline. The latter deliberately bypasses the browser cache during asset updates, while author mode exposes filter-source and debugging tools. [uBlock Origin documents these advanced settings and their intended use](https://github.com/gorhill/uBlock/wiki/Advanced-settings).

The shared dynamic rules start with global third-party script and frame blocking. That is uBlock's medium mode. The official documentation describes it as a strong privacy and performance mode that requires the user to unbreak sites and can produce high breakage. [The uBlock Origin medium-mode guide describes its guarantees and maintenance cost](https://github.com/gorhill/uBlock/wiki/Blocking-mode:-medium-mode). The long per-site noop list in the repository confirms that cost.

Treat medium mode as a personal, opt-in profile choice. For a high-compatibility default, use uBlock's normal mode with stock lists. If medium mode remains, keep the rule set in `homes/*/local` and share it between Firefox and Zen on that host.

## Performance guidance

Keep hardware acceleration enabled by default. Mozilla recommends the default performance settings for most users and explains that hardware acceleration offloads graphics work to the GPU, reducing CPU use. [Mozilla documents Firefox performance settings](https://support.mozilla.org/en-US/kb/performance-settings).

Do not apply all Fastfox preferences on every operating system and GPU. Performance preferences can interact with the compositor, graphics stack, memory, and workload. Use browser defaults plus measured host-local exceptions.

`modules/home/zen-browser/acceleration.nix` force-enables Linux video-decoding preferences for Zen only, even though its comment describes a current NVIDIA path. Move that overlay to the affected NixOS host and apply equivalent settings to Firefox if the same Firefox version and driver need them. Do not send the overlay to Darwin.

The four duplicated scrolling profiles can become one shared selector. Keep only the selected preset active. Scrolling feel is a UX choice, so the selection belongs in local configuration while the preset definitions can live in the shared browser library.

## Zen-specific behavior and limitations

Keep the following outside the shared Firefox data:

- spaces, essentials, pins, folders, and workspace routes
- joined tabs and live folders
- Zen keyboard shortcuts and extension-button placement
- Zen Mods and Sine integration
- `zen.*` preferences and Zen UI CSS

The Zen module updates some profile state while the browser is closed and skips the activation safely when the profile lock is held. [The pinned Zen Home Manager module documents and implements its activation behavior](https://github.com/0xc000022070/zen-browser-flake/tree/382e4f584c03b750d35849faff70ac1aa44fd6cf/hm-module). Rebuilds that change spaces or pins should therefore be applied with Zen closed, then checked after launch.

The repository uses the Twilight channel. Zen describes Twilight as an early testing channel for upcoming Firefox releases, while its beta channel follows the supported daily-browser release path. [Zen documents its release timing and security update process](https://docs.zen-browser.app/security). Prefer beta for the primary daily browser when compatibility and stability rank above early features. Keep Twilight only if testing upcoming changes is intentional.

Keep Firefox installed on macOS even if Zen is primary. Zen's FAQ states that Widevine DRM is unavailable on macOS and Windows, so DRM-dependent streaming services need another browser. [Zen documents the Widevine limitation in its FAQ](https://docs.zen-browser.app/faq?pubDate=20250213).

The current Zen version is newer than the fix for the unsigned-updater vulnerability affecting versions through 1.19.8b. Zen's advisory states that 1.19.9b fixed the issue. [Zen's GHSA advisory provides the affected and patched versions](https://github.com/zen-browser/desktop/security/advisories/GHSA-qpj9-m8jc-mw6q). Nix ownership plus disabled in-app updates also avoids depending on Zen's MAR updater.

## Native messaging

Neither browser currently configures `nativeMessagingHosts`. Both modules support it, so one shared package list can be assigned to both only when an installed extension needs a native companion.

Native messaging gives an extension a channel to a native process. Mozilla requires the extension's `nativeMessaging` permission plus a host manifest that limits the allowed extension IDs. [MDN documents the permission, manifest, and message transport](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging). That is a wider trust boundary than a browser-only extension, so do not add hosts speculatively.

Home Manager installs manifests in the platform-specific Mozilla native-messaging directory, including `Library/Application Support/Mozilla/NativeMessagingHosts` on macOS and `.mozilla/native-messaging-hosts` on Linux. [The pinned Home Manager implementation defines those paths](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/misc/mozilla-messaging-hosts.nix). The Zen Darwin package mode consumes the same Home Manager host option. Add a host such as a PWA or command-line integration only together with its extension and a documented use case.

## Implemented layout

```text
lib/browser/
  extensions.nix
  ublock.nix

modules/home/browsers/
  default.nix
  shared/
    default.nix
    default-browser.sh
    extensions.nix
    profile.nix
    search.nix
    ublock.nix
  firefox/
    default.nix
  zen/
    default.nix

homes/macbook-pro-m4/local/browsers/
  default.nix

homes/desktop/local/browsers/
  default.nix

homes/shared/local/browsers/
  common.nix
  extensions.nix
  search.nix
  zen.nix
```

`lib/browser/` contains only the extension-policy and uBlock serialization functions. All browser settings and policy data live with the browser modules. The shared Home Manager modules expose their common data through internal, read-only `programs.browserSuite.shared` options. They do not inject module arguments. The Firefox and Zen modules attach that configuration to each program and contain only genuine browser differences. Personal declarations live below `homes/*/local/browsers/`; the two machines import their shared personal choices from `homes/shared/local/browsers/`.

Examples of personal/local configuration:

- default and private search engine
- AI, YouTube, Cornell, and other personal search providers
- medium-mode uBlock rules and per-site exceptions
- Karakeep, Simplify Jobs, Refined GitHub, SponsorBlock, and UI extensions
- bookmarks, homepage, containers, profile availability, and Sync policy
- Zen spaces, pins, routes, shortcuts, mods, and button placement
- DoH ownership and GPU/video-decoding overrides
- which browser becomes the operating-system default

Examples of appropriate shared configuration:

- a conservative privacy and security policy baseline
- uBlock Origin definition and safe common settings
- extension policy helper data
- neutral Nix and GitHub search-engine definitions
- language packs and profile identity shape
- reviewed compatibility preferences
- native messaging host wiring, when a shared companion is actually installed

## Completed migration

1. Created the browser folder, shared interface, and reusable library.
2. Unified extension, search, uBlock, profile, scrolling, policy, and default-browser behavior.
3. Replaced legacy search fields and raw preference stacks with typed Home Manager settings.
4. Moved personal providers, workflow extensions, default-browser choice, Zen workspaces, and host resolver policy into local modules.
5. Selected Zen beta for the daily browser and preserved signed Darwin application bundles for both browsers.
6. Added a focused `browser-configuration-contract` flake check and verified the generated search, policy, extension, default-browser, and application artifacts.

## Verification checklist

After implementation:

- Evaluate and build every affected Home Manager configuration, not only the current host.
- Inspect `about:policies` in both browsers for active and rejected policies.
- Inspect `about:config` for the final value and source of each deliberate privacy override.
- Inspect `about:support` for extension IDs, graphics acceleration, codec support, profile paths, and enterprise-policy status.
- Confirm Firefox and Zen both receive the intended search engines and that each URL substitutes `{searchTerms}` correctly.
- Test private browsing, Bitwarden, uBlock, Safe Browsing, certificate failures, an HTTP-only local service, local DNS names, video calls, screen sharing, WebGL, hardware video decoding, PDF download behavior, and DRM playback.
- Test sites that previously required uBlock noop rules before deleting any compatibility exceptions.
- On macOS, verify LaunchServices opens HTTP and HTTPS links in the selected default browser.
- Apply any Zen state changes with Zen closed, then verify spaces, pins, and shortcuts after launch.
- Keep Firefox as the compatibility fallback until Zen passes the workflows that depend on Widevine or other platform integrations.
