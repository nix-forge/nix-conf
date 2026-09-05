# Implementation plan: Dual-profile Firefox

This plan is superseded by the [Zen Shopping decision](../../browser-shopping-profile-research.md).
The implemented profile lives in Zen and includes the Rakuten extension. The
Firefox design below is retained as the record of the earlier choice.

## Selected design

The user selected a separate Firefox profile on 2026-09-02 after clarifying that Firefox must remain useful for ordinary browsing. Zen stays the system default browser. Firefox keeps its existing default profile as `Personal` and adds a non-default `Shopping` profile for Rakuten transactions.

Purchases start at Rakuten.com, so the Rakuten extension is not installed. The setup uses Firefox's profile menu or `about:profiles`; it does not create another macOS application or Dock item.

## Module design

`programs.browserSuite.firefox.shopping` is the interface. It exposes only `enable`, `profileName`, `profilePath`, and `startUrl`. The implementation creates profile ID 1, applies shared security and scrolling settings, selects Standard tracking protection for checkout compatibility, disables Firefox account and form-fill behavior in that profile, and clears transaction state on a clean shutdown.

Firefox application policies remain appropriate for Personal. The Shopping behavior uses profile preferences because enterprise policies apply to every profile in the Firefox application.

## Extension ownership

- Nix blocks undeclared extensions with the wildcard policy.
- Bitwarden is shared and required, so Firefox installs it in both profiles.
- Approved daily extensions are `allowed` in Firefox rather than automatically installed.
- Mozilla Multi-Account Containers remains allowed for ordinary Firefox use.
- Firefox owns the installation and updates of those allowed extensions in Personal.
- Zen continues to install its declared daily extensions automatically and requires uBlock Origin.
- A fresh Shopping profile contains only Bitwarden unless the user manually installs another approved extension.

This split preserves browser-managed updates. It cannot enforce exact per-profile membership because Firefox's enterprise extension policy is application-wide. Home Manager profile packages would enforce membership but would make Nix own extension versions and updates, so this implementation does not use them.

## Compatibility and migration

The existing Firefox `Profiles/default` directory remains the default and is not deleted or rewritten. The `Profiles/shopping` directory is separate. The install-registry reconciler continues to point ordinary Firefox launches at `Profiles/default`.

Extensions already installed in Personal remain permitted and Firefox can update them. If an earlier activation removed one, reinstall it once from AMO; the allowlist permits only the declared IDs.

Shopping clears cookies and storage, cache, browsing and download history, form data, sessions, offline data, and site settings on a clean shutdown. Downloaded receipt files remain on disk. Crash recovery remains enabled until Firefox exits normally.

## Validation

- Build `checks.x86_64-linux.browser-configuration-contract` from a complete source tree.
- Assert Personal is the default profile at `Profiles/default`.
- Assert Shopping is non-default at `Profiles/shopping`.
- Assert app-wide Firefox policies remain Strict and do not enable global shutdown sanitization.
- Assert Shopping alone selects Standard tracking protection and shutdown cleanup.
- Assert Bitwarden is the only automatically installed Firefox extension.
- Assert daily Firefox extensions use `allowed`, omit `install_url`, and keep browser updates enabled.
- Assert Zen retains automatic extension installation and required uBlock Origin.
- Assert no Firefox Shopping launcher package or Dock item exists.
- Run the Gecko install-registry test.

## Rollout

Activate while Firefox is closed. Open Firefox normally and confirm Personal retains its history and extensions. Open the Firefox profile menu or `about:profiles`, launch Shopping, and confirm its orange top border and Rakuten homepage. Complete a low-value eligible purchase before using the workflow for a large transaction.

After Rakuten confirms the shopping trip, close the Shopping window normally. Reopen Shopping and verify that history and sign-in state were cleared. Confirm that Personal still retains its normal session and history.

## Rollback

Disable `programs.browserSuite.firefox.shopping`, restore the previous Firefox extension installation modes, and reactivate the Home Manager generation. Do not delete either profile directory automatically.

## Implementation result

Implemented on 2026-09-02. The browser configuration contract and Gecko registry test cover the configuration. Runtime cashback attribution still requires the documented low-value purchase after activation.
