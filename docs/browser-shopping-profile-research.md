# Browser shopping profile research

> Decision update, 2026-09-02: The user accepted Rakuten's extension privacy
> risk and the lack of official Zen support. The implemented design now uses a
> separate Zen Shopping profile with Rakuten installed only there. The original
> compatibility-first Firefox analysis remains below as decision history.

Research date: 2026-09-02

## Recommendation

Do product research in Zen with uBlock Origin enabled. Make the purchase in a separate, visibly named `Shopping` browser context. Start the purchase at Rakuten.com and follow its store link. The Rakuten extension is optional, so the most private setup does not install it at all.

For this repository, the best fit is one Firefox application with separate `Personal` and `Shopping` profiles while Zen remains the default browser. This preserves Firefox for ordinary use and keeps shopping cookies, history, settings, and add-ons out of its normal profile. On macOS, a Safari `Shopping` profile is another supported option, but it adds another browser to the workflow.

Give the Shopping profile a different theme color and a Rakuten.com start page. Keep Personal as Firefox's default profile and switch with Firefox's profile menu or `about:profiles`; no extra macOS application or Dock item is needed. Mozilla supports choosing and opening separate profiles, including concurrent instances through the profile command-line options. [Firefox profile manager](https://support.mozilla.org/en-US/kb/profile-manager-create-remove-switch-firefox-profiles) and [Firefox command-line options](https://wiki.mozilla.org/Firefox/Command_Line_Options)

This is a deliberate compromise. Cashback attribution is tracking. The goal is to confine that tracking to a short transaction session rather than pretend it can be removed while still receiving the cashback.

## Documented facts

### The Rakuten extension is not required

Rakuten says a shopping trip begins when the member clicks a Rakuten link on Rakuten.com, in its app, or in its browser extension. Its basic instructions list the website, app, and extension as alternatives. The member must start the trip through Rakuten and finish the purchase in the same shopping session. [Rakuten's shopping-trip explanation](https://www.rakuten.com/help/article/what-is-an-rakuten-shopping-trip-360002100588) and [How Rakuten works](https://www.rakuten.com/help/article/how-rakuten-works) document this.

Cookies must work for Rakuten and the merchant. Rakuten also warns against visiting competing coupon or rewards services after activation, using unapproved coupon codes, changing windows, or beginning a second purchase without starting another trip. These actions can transfer attribution away from Rakuten. [Rakuten's program terms](https://www.rakuten.com/help/article/terms-conditions-ebates-mode-115009325528), [shopping-trip explanation](https://www.rakuten.com/help/article/what-is-an-rakuten-shopping-trip-360002100588), and [rewards-extension compatibility note](https://www.rakuten.com/help/article/can-i-use-the-rakuten-browser-extension-with-other-coupon-or-rewards-sites-360002117327) describe those constraints.

### The extension has a broad privacy cost

Rakuten's current extension terms say the extension collects page URLs, searches, product views, cart contents, and other shopping information even when the user is not interacting with it. It also reads order-confirmation data. Rakuten says uninstalling is the way to stop all extension collection. [Rakuten Browser Extension Terms](https://www.rakuten.com/help/article/rakuten-browser-extension-terms-360052819794)

The Firefox listing requests access to browser tabs, navigation activity, and data for all websites. [Rakuten on Firefox Add-ons](https://addons.mozilla.org/en-US/firefox/addon/ebates/)

Rakuten officially supports Firefox, Chrome, Safari, and Edge. It says third-party browsers are not guaranteed to work. Zen therefore should not be the transaction browser even though it is Firefox-derived. [Rakuten supported browsers](https://www.rakuten.com/help/article/supported-browsers-360002101188)

### Ad blocking and privacy modes

Rakuten tells uBlock Origin users to disable the blocker for the shopping trip and re-enable it afterward. Its only documented automatic allow-list flow is for AdBlock. Rakuten also recommends avoiding private browsing and VPN use for cashback transactions. [Rakuten's software and settings guidance](https://www.rakuten.com/help/article/software-or-settings-preventing-cash-back-360002100568)

uBlock Origin can disable filtering for a hostname or page through its trusted-sites control. This does not prove that allow-listing only `rakuten.com` and a merchant will cover every affiliate redirect and tracking origin in a shopping trip. Rakuten does not promise that it will. [uBlock Origin trusted-sites documentation](https://github.com/gorhill/uBlock/wiki/How-to-mark-a-web-site-as-trusted)

Firefox's Standard tracking protection still includes Total Cookie Protection. Mozilla recommends a per-site tracking-protection exception when that partitioning breaks a site, rather than disabling protection everywhere. [Mozilla's Total Cookie Protection guide](https://support.mozilla.org/en-US/kb/introducing-total-cookie-protection-standard-mode)

## Isolation choices

| Choice | What it isolates | Limitation | Verdict |
| --- | --- | --- | --- |
| Separate supported browser | Browser data and installed extensions are kept in that application's profile directory | It still runs as the same OS user and is not a VM or malware boundary | Best simple boundary when Zen remains the daily browser |
| Firefox profile | Mozilla says profiles separate cookies, logins, history, settings, bookmarks, passwords, and add-ons | Firefox enterprise extension policies are application-wide in this configuration | Best cross-platform UX once policy handling is adjusted |
| Safari profile | Apple separates history, cookies, site data, and extension enablement by profile | Passwords, AutoFill, security, website, and privacy settings remain shared | Best immediate macOS UX |
| Multi-Account Container | Cookies, logins, and site data are separated inside one Firefox profile | Add-ons and profile settings are shared, so it does not confine the Rakuten extension | Useful only for an extension-free shopping workflow when a full profile is unavailable |
| Private browsing | Firefox discards private-session cookies and history and excludes extensions unless allowed | Rakuten recommends against it, and Firefox containers do not operate in private windows | Do not use for cashback purchases |

Mozilla explicitly distinguishes profiles, which separate all profile data and add-ons, from containers, which separate only cookies, logins, and site data. [Firefox profile management](https://support.mozilla.org/en-US/kb/profile-management) and [Multi-Account Containers](https://support.mozilla.org/en-US/kb/containers)

Firefox can place sites from different containers into separate site-specific renderer pools. That process separation protects web content. It does not turn a container into an add-on permission boundary. [Firefox process model](https://firefox-source-docs.mozilla.org/dom/ipc/process_model.html)

Private browsing discards its cookies and site data at the end of the session, but it does not provide anonymity or protection from host malware. Extensions are disabled there unless separately granted access. [Firefox Private Browsing](https://support.mozilla.org/en-US/kb/private-browsing-use-firefox-without-history) and [extensions in private windows](https://support.mozilla.org/en-US/kb/extensions-private-browsing)

Apple documents that Safari 17 profiles separate history, cookies, website data, and extensions. Safari extensions are installed application-wide but can be enabled independently for each profile, and new profiles start with extensions disabled. [Apple's Safari profile guide](https://support.apple.com/en-us/105100)

## Suggested workflow

1. Research products and compare prices in Zen. Keep uBlock Origin and Strict tracking protection on.
2. Copy only the final merchant or product URL. Do not carry a large research session into the shopping context.
3. Open the clearly colored `Shopping` profile or dedicated purchasing browser. Do not use a private window.
4. Sign in to Rakuten.com, inspect the merchant's current exclusions, and click Rakuten's merchant link. The extension is not needed.
5. Confirm that Rakuten reports an active shopping trip. Stay in the same transaction window, avoid competing rewards links, and use only coupon codes that Rakuten permits.
6. Complete checkout in that session. Keep cookies enabled until the order confirmation and shopping-trip record appear.
7. Save the receipt outside the browser if needed and check that Rakuten recorded the shopping trip. Then close the shopping context. Provide a deliberate reset action for clearing its cookies and site data rather than clearing automatically at shutdown. An accidental close during checkout should not destroy Rakuten's required session.

Use Firefox Standard tracking protection in the shopping context first. If activation fails, use Firefox's shield control to relax protection only for Rakuten and the current merchant, then restart the trip. Do not lower the protections in Zen.

## Extensions for the shopping context

Keep the list short.

- Keep Bitwarden. It is already present in the repository, is a Mozilla Recommended extension, and provides the login and payment autofill value needed during checkout. [Bitwarden on Firefox Add-ons](https://addons.mozilla.org/en-US/firefox/addon/bitwarden-password-manager/)
- Do not add Honey, Capital One Shopping, other coupon tools, or competing cashback extensions. Rakuten says competing reward and coupon services can take over attribution.
- Do not add URL-cleaning extensions. Removing affiliate parameters can defeat the shopping trip.
- Keep uBlock Origin out of the shopping profile, or disable it only in that profile during purchases. Keep it enabled in Zen.
- Keepa is a defensible optional tool for Amazon price research because its Firefox permissions are limited to Keepa and Amazon domains. It still reports the viewed product identifier to Keepa, and it adds no checkout security. Use the Keepa website or install it in the research profile, not the transaction profile. [Keepa on Firefox Add-ons](https://addons.mozilla.org/en-US/firefox/addon/keepa/)

No additional shopping extension adds enough security or purchasing value to justify access to checkout pages. The profile should contain Bitwarden and, only if the extension workflow is preferred over Rakuten.com, Rakuten.

## Fit with the current Nix configuration

The repository already has the right broad split. Zen is the default browser, Firefox is installed, Firefox supports multiple profiles, Bitwarden is configured, and the common profile keeps Safe Browsing and certificate checks enabled.

Two current policy choices prevent clean per-profile extension behavior:

1. [`lib/browser/extensions.nix`](../lib/browser/extensions.nix) emits `"*" = { installation_mode = "blocked"; }` and automatically installs every declared Firefox extension.
2. [`modules/home/browsers/firefox/default.nix`](../modules/home/browsers/firefox/default.nix) attaches `ExtensionSettings` at the application policy level, outside `profiles`. The policy therefore cannot express "install Rakuten only in the shopping profile." uBlock Origin is also `force_installed`, so a shopping profile cannot disable it normally.

Mozilla provides an `allowed` installation mode. It permits a named extension without automatically installing it. Adding an `allowed` catalog mode would let Nix keep the deny-by-default extension allow-list while the user installs Rakuten only in the shopping profile. `normal_installed`, which the current code uses for non-required entries, automatically installs the extension and is the wrong mode for this case. [Mozilla ExtensionSettings reference](https://firefox-admin-docs.mozilla.org/reference/policies/extensionsettings/)

The remaining uBlock issue needs one explicit product decision. Either dedicate the whole Firefox application to purchasing and omit uBlock there, or stop force-installing uBlock so it can remain enabled in ordinary profiles and disabled in `Shopping`. If neither tradeoff is acceptable, use a Safari `Shopping` profile on macOS. Containers cannot solve this policy problem.

## Facts, inferences, and recommendations

- Documented fact: Rakuten.com can start a cashback trip without the browser extension.
- Documented fact: Rakuten requires working cookies and recommends disabling uBlock Origin during the trip.
- Documented fact: Firefox profiles separate add-ons and site data; containers do not separate add-ons.
- Inference: a container cannot stop the broadly permissioned Rakuten extension from observing ordinary tabs in the same profile.
- Inference: a hostname-only uBlock allow-list may miss an affiliate redirect, so it is less reliable than a blocker-free transaction profile.
- Recommendation: use an extension-free, dedicated shopping profile or browser and start every purchase at Rakuten.com. Install Rakuten only inside that context if its reminders or coupon automation prove necessary.
