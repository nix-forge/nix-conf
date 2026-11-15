# Refined GitHub installation and token provisioning

Reviewed: 2026-10-08. Scope: Refined GitHub AMO 26.10 and upstream commit `601f6fa3ce70b93e170c8144442995714f66ec6c`; Firefox WebExtensions APIs inherited by Zen.

## Answer

Install the official signed extension declaratively, then use a dedicated expiring classic personal access token through its normal options page. Stock Refined GitHub does not support declarative token provisioning through Firefox enterprise policies, managed storage, native messaging, or a token-file setting. Encryption through nix-seal can protect the authoritative credential and an optional runtime import file, but the extension ultimately persists the imported token in unencrypted browser extension storage. These are separate security properties.

For a dependable setup now, use the signed AMO release and manual token entry or its supported Import button. If automatic runtime provisioning is a requirement, the best maintainable direction is an upstream change to read managed token storage without copying it into synced options. A private patched extension can do this, but carries signing and update work. Direct browser database edits are a poor interface for configuration management.

## Findings and sources

### Why installation was missing

The shared [home extension catalog](../../homes/shared/local/browsers/extensions.nix) declared the correct AMO ID and slug, but mapped Refined GitHub to `mode = "allowed"` in both browsers. The [policy generator](../../modules/home/browsers/shared/extension-policies.nix) deliberately omits the download URL for that mode. Mozilla defines `allowed` as permitting user installation and `normal_installed` as automatic installation with user disablement available. See the [ExtensionSettings reference](https://firefox-admin-docs.mozilla.org/reference/policies/extensionsettings/).

Local observation confirmed the active Zen profile had no Refined GitHub entry in its extension registry. The deployed Zen package had an explicit `allowed` policy without an `install_url`. This matches the catalog rather than an invalid AMO identifier or a missing token. AMO metadata and the signed XPI both report ID `{a4c4eda4-fb84-4a84-b4a1-f7c1cbf2a1ad}`, slug `refined-github-`, release `26.10`, and minimum Firefox version `133.0`.

The [desktop home profile](../../homes/desktop/default.nix) also omitted the Firefox feature. The macOS home profile still selected it. The repair restores Firefox on the desktop and explicitly sets Refined GitHub to `mode = "normal"` in the common daily catalog. This produces automatic installation in both browsers and retains AMO updates. Policies apply application-wide, including the separate Zen shopping profile; the extension can be disabled there if unwanted. The token remains a per-profile setting.

### Token behavior and access

Most features modify GitHub's page directly and work without a token. API features need a token, and GraphQL requests refuse to run without one. A token cannot explain why the extension itself is absent. The [upstream security guide](https://github.com/refined-github/refined-github/wiki/Security), reviewed on this date, says fine-grained tokens are unsupported. This is the current supported-product position despite older discussion about basic acceptance.

The [options](https://github.com/refined-github/refined-github/blob/601f6fa3ce70b93e170c8144442995714f66ec6c/source/options-storage.ts) store `personalToken` as an array of strings. The UI supports three account tokens, and [token selection](https://github.com/refined-github/refined-github/blob/601f6fa3ce70b93e170c8144442995714f66ec6c/source/github-helpers/github-token.ts) chooses by the logged-in user when several exist, with a fallback to the first token. This is account selection, not a general engine for choosing fine-grained tokens by repository. GitHub Enterprise origins have separate options through the per-domain storage library.

The [API implementation](https://github.com/refined-github/refined-github/blob/601f6fa3ce70b93e170c8144442995714f66ec6c/source/github-helpers/api.tsx) sends the token in HTTPS authorization headers to GitHub REST and GraphQL APIs. It checks that token ownership matches the logged-in account before REST writes and GraphQL mutations. Read requests remain possible with a different account's token. Token ownership and expiration are validated by requests to the API root and `/user`.

The [scope UI](https://github.com/refined-github/refined-github/blob/601f6fa3ce70b93e170c8144442995714f66ec6c/source/options/token-input.svelte) distinguishes public reads, public writes, private repository access, project reads, workflow edits, and optional repository deletion. Its generator link, also confirmed in the signed 26.10 package, asks for `repo,read:project,workflow` and preselects no expiration. Change the expiration choice deliberately.

| Intended use | Classic PAT scopes |
| --- | --- |
| Public REST reads only | No scopes |
| Public repository GraphQL enhancements and writes | `public_repo`, plus `read:project` when project checks matter |
| Private repository reads and writes | `repo`, plus `read:project` when needed |
| Edit Actions workflow files | Add `workflow` only when needed |
| Quick repository deletion | Add `delete_repo` only if deliberately enabling that action |

GitHub's [scope documentation](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps) confirms that `repo` and `public_repo` include write access. GitHub's current [GraphQL authentication guide](https://docs.github.com/en/graphql/guides/forming-calls-with-graphql) explicitly asks for `public_repo` for public repository GraphQL access with classic PATs. The extension UI's generic valid-token indicator does not establish that a no-scope PAT covers every public read enhancement. There is no blanket `read:user` requirement in the current guide; requested fields determine access. There is no general read-only classic PAT scope for private repository contents. Therefore full private repository support in the officially supported token model requires a credential with broader authority than a read-only browser enhancement would ideally receive. Do not add organization administration, package administration, or deletion scopes by default.

The options input accepts arbitrary token strings of sufficient length, so a fine-grained PAT may validate. But [scope parsing](https://github.com/refined-github/refined-github/blob/601f6fa3ce70b93e170c8144442995714f66ec6c/source/github-helpers/github-token.ts) records `valid_token,unknown` when OAuth scope headers are absent. Features explicitly requiring `read:project` or `delete_repo` then fail their scope checks. GitHub's [PAT guide](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) describes fine-grained resource-owner and repository restrictions. Source acceptance does not establish complete feature support. Choose fine-grained tokens only as a deliberately limited, tested setup with expected feature failures.

The upstream guide suggests a GitHub CLI OAuth token when an organization blocks classic PATs. Organization OAuth restrictions and SSO authorization still apply. Reusing a CLI credential also shares its permissions and revocation with the browser extension; a dedicated PAT provides better isolation when permitted.

### Why policies cannot supply the stock token

Firefox supports administrator-provided [managed extension storage](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/storage/managed) through a native storage manifest or the `3rdparty` policy. Firefox does not require the Chrome managed-storage schema manifest key. Missing such a schema alone would not prove absence of support.

Here the determining evidence is actual code. Refined GitHub delegates options to `webext-options-sync-per-domain` 4.3.2. Its [pinned implementation](https://github.com/fregante/webext-options-sync-per-domain/blob/ec0f05483d65191b69a579bcfbb0aba695d93913/index.ts) creates `OptionsSync` instances without overriding storage type. The [locked dependency](https://github.com/refined-github/refined-github/blob/601f6fa3ce70b93e170c8144442995714f66ec6c/package-lock.json) is `webext-options-sync` 4.4.0-0. Its [implementation](https://github.com/fregante/webext-options-sync/blob/dd789f4a28630be8246ce4d511d4a7bbbdfcb695/index.ts) defaults to `storage.sync`, reads the `options` key, and never reads managed storage. The official signed XPI contains the same behavior. Setting `3rdparty.Extensions.<id>.personalToken` would place data in a namespace the extension never consults.

The dependency compresses options with LZ-string before storage. Compression is reversible encoding, not encryption. A preference in `user.js` also cannot supply this extension-scoped options object.

[Mozilla's storage documentation](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/storage) states that extension storage is unencrypted. Refined GitHub warns that tokens can sync with the browser vendor when extension sync is enabled. Disabling extension-data sync reduces replication, but does not encrypt the local token. The current [Firefox extension-storage sync engine](https://github.com/mozilla-firefox/firefox/blob/main/services/sync/modules/engines/extension-storage.sys.mjs), retrieved on the review date, defaults to the Add-ons sync selection but honors `services.sync.engine.extension-storage.force = false` independently. This is a targeted candidate for preventing extension-data synchronization while retaining other sync engines, including tabs and ordinary add-on installation sync. Verify the deployed Firefox and Zen versions before relying on it; setting it does not erase an existing server-side copy. Do not substitute the similarly named `webextensions.storage.sync.enabled`; it is a different preference, and the inspected current parent API source uses it for telemetry gating rather than as the explicit engine-selection switch.

### Runtime choices

| Approach | Status and cost |
| --- | --- |
| Dedicated PAT entered manually | Supported and simple; retained in ordinary browser storage |
| nix-seal runtime JSON imported through the options UI | Supported import path; authoritative value stays encrypted in configuration, but the browser keeps a copy |
| Browser automation of options UI | Technically possible, but requires browser control, careful secret transport, and UI maintenance; still writes ordinary browser storage |
| Offline SQLite or IndexedDB edits | Private browser format, unsafe with an open browser, possible sync overwrite; avoid |
| Managed-storage upstream support | Best small interface for automatic provisioning; needs extension change and a protected runtime manifest |
| Native messaging broker | Requires extension changes, `nativeMessaging` permission, a native host, and request authorization; considerably more work |

For optional import, open the extension options, expand "Export options", and choose "Import". The options library recognizes a JSON object with `__webextOptionsSync: "Refined GitHub"` and `personalToken: ["<TOKEN>"]`. Its Import button merges specified options. Confirmed in AMO 26.10. A minimal runtime file has this shape:

```json
{
  "__webextOptionsSync": "Refined GitHub",
  "personalToken": ["<TOKEN>"]
}
```

The placeholder is illustrative and must never be replaced in a committed file. Render this only through a protected nix-seal runtime template with JSON escaping. Never put the rendered value in a Nix string, derivation, Git file, command argument, log, or captured browser session. A template supports repeatable credential distribution, but import remains an explicit UI action and rotation requires reimporting. Export also includes the token, as the options UI warns.

A future managed implementation should read runtime managed tokens separately from synced ordinary settings, exclude them from options export and autosave, and define precedence and per-origin behavior. A user-owned 0600 native storage manifest can be rendered by nix-seal. Firefox loads managed storage at browser startup, so rotation requires a restart. The deployed Zen build's manifest lookup behavior needs runtime testing. A runtime policy file is also possible, but placing it in a Nix-store-generated `policies.json` leaks the secret and can complicate separation from public installation policies.

The stock [manifest](https://github.com/refined-github/refined-github/blob/601f6fa3ce70b93e170c8144442995714f66ec6c/source/manifest.json) does not request `nativeMessaging`. A native host alone cannot supply a token to this extension. A patched broker design could keep the PAT out of browser storage by performing approved GitHub requests itself. Returning the PAT to the extension instead only removes persistent browser storage, not token access in browser memory. Mozilla's [native messaging documentation](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging) requires explicit extension permission and allowed extension IDs.

A private modified extension needs its own release process. Mozilla requires [signing for release Firefox](https://extensionworkshop.com/documentation/publish/signing-and-distribution-overview/), including self-distributed extensions. Keep the official signed extension and its normal updates unless automatic secret provisioning justifies that maintenance burden.

## Validation and limits

Fetched and inspected the official [AMO 26.10 XPI](https://addons.mozilla.org/firefox/downloads/file/5075070/refined_github-26.10.xpi) in memory. SHA-256: `ee4784797ac6af961e8bdea62767357a753dbfefbad51a25a04746d6156ea192`. Confirmed permissions, token array storage, generator scopes, Import and Export buttons, default sync storage, and absence of managed-storage and native-messaging access. Inspected upstream source and exact dependency revisions named above. Browsed current primary documentation.

No credential was read, generated, or submitted. No browser API operation or authenticated feature was tested. No native manifest was deployed. One research request for AMO metadata failed with HTTP 401; a separate coordinator request succeeded and confirmed the GUID, slug and version. The signed download also succeeded. A GitHub recursive dependency-tree request hit unauthenticated rate limits; raw source and npm package metadata supplied the pinned evidence instead. These limits do not alter the inspected packaged behavior.

Focused evaluation used the real extension option module and policy generator with the installed Nixpkgs library. Against the existing staged catalog, both policies were `allowed` with no URL. Against the repaired catalog, both were `normal_installed` with the AMO latest URL; all catalog assertions passed. Nix formatting, deadnix, catalog statix and patch whitespace checks passed on Linux. Research Markdown lint, spelling, local links and a Gitleaks publication scan passed. Full desktop evaluation was submitted through `workstation-task` and then cancelled while queued behind other work; it did not run. No full system build, activation or Darwin runtime test was performed.

## Implication for this repository

Keep installation policy and token provisioning separate. Repair extension installation first. Prefer a dedicated expiring classic PAT with scopes chosen for actual feature use; full private support needs `repo`. Use the existing sealed-secret integration if storing a canonical credential or runtime import template. Do not add a token-bearing Firefox policy to the ordinary Nix configuration. If unattended provisioning is required, propose managed-storage support upstream and assess signing and updates before implementing a fork. The [secret-management guide](../secrets.md#config-templates) describes runtime templates and their ownership requirements. The integration now uses a dedicated classic token. The initial temporary reuse and subsequent deployment are recorded below.

### Temporary reuse through nix-seal

The initial shared [home secret module](../../homes/shared/local/nix-seal.nix) declared `nixSeal.templates.refined-github-token-import` with a placeholder for the existing `nix-token-github-com` field, avoiding duplicate ciphertext or a new credential. The template contains the supported import marker and token array, and renders with mode `0400`. Both home profiles inherit it. The actual GitHub token must contain only letters, digits and underscores because nix-seal UTF-8 substitution does not escape JSON; that condition was checked before preparing the file.

For immediate use, an equivalent import file was prepared in the existing user-owned nix-seal runtime directory, outside its signed generation. Its JSON was compared against the declared template without printing the credential. The Linux mount was verified as `tmpfs,noswap`, and the prepared file is owner-readable only. This file is ephemeral; the declarative template supplies the lasting configuration after secret preparation and activation. Choose the file with Refined GitHub's Import button in each intended browser profile. Rotation requires reimporting.

Reusing a credential does not add permissions or change token type. Authentication was checked successfully against GitHub without printing account information or token values. Full feature coverage remains unverified, especially if the reused credential is fine-grained. No browser storage was modified. Installing the extension and importing the file remain distinct steps; the earlier installation policy repair has not been activated by this work.

The new template was evaluated with the installed Nixpkgs library and nix-seal's real placeholder parser. It resolves exactly the existing token field. Nix formatting, deadnix, statix and patch whitespace checks passed. Full signed-plan preparation, system activation, and browser feature testing were not performed.

### Linux activation verification, 2026-10-09

The full desktop system built successfully through the workstation queue. Signed
secret preparation passed its dry run, installed the host and home artifact
batches, and passed destination readiness. The resulting system was activated
and selected as the boot default. Both installed browser packages contain
`normal_installed` for Refined GitHub with the AMO update URL. Firefox is present
in the activated home environment. No failed system or user units were reported
immediately after activation.

The activated nix-seal template was parsed as JSON and compared against the
current runtime Nix GitHub token without printing either value. Its owner and
`0400` mode were verified. The browser options import has not been performed;
a restart and per-profile import are still required. Token permissions and
fine-grained-token compatibility still limit full feature coverage.

### Dedicated credential, 2026-10-11

The shared home policy now declares `refined-github-token`, stored as canonical
age ciphertext under `homes/shared/local/secrets/`. The import template references
this field. The Nix access credential retains its separate declaration and
value. Token authentication and the recommended `repo`, `read:project`, and
`workflow` scopes were verified without printing the token or account data.

Creation used nix-seal's generated bootstrap plan and authorized create-only
operation, with plaintext supplied through standard input. Signed host and home
artifact preparation and destination readiness passed. User runtime activation
and a restart of the native login activation service passed. The deployed service
uses the tested installed CLI with the new signed plan; this credential update
does not require an unrelated CLI or complete system upgrade. Its public store
references are retained until normal Home Manager activation replaces them.

The import JSON remains owner-readable with mode `0400` in the private noswap
runtime. User tmpfiles maintains a stable `.json` symlink to the current template,
so reboot recreation and secret generation changes do not require a plaintext
copy. Import this file in each intended browser profile. Browser storage has not
been modified by the provisioning commands; importing and testing extension
features remain separate steps.
