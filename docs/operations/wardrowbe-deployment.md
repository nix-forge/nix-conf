# Wardrowbe deployment

The desktop uses the [Wardrowbe v1.10.1 release](https://github.com/Anyesh/wardrowbe/releases/tag/wardrowbe-v1.10.1) through two native packages from `pkgs/`. The reusable `services.wardrowbe` module lives in `nix-homelab/`. It runs FastAPI, two bounded job workers and the Next.js frontend behind the existing LAN HTTPS proxy. PostgreSQL holds wardrobe data, Redis holds jobs, and uploaded images live in `/var/lib/wardrowbe/uploads`.

The module accepts HTTPS OIDC issuers, including realm paths. The desktop uses
[native Keycloak](https://www.keycloak.org/) for password-first sign-in and optional
Bitwarden passkeys. Wardrowbe uses a confidential client with PKCE, exact callback
and logout URLs, and `client_secret_basic`. Production API requests require OIDC;
development login must not be enabled on the LAN site.

## First enrollment

Three nix-seal bundles hold the initial realm, administrator environment and
Wardrowbe environment. The complete realm document is encrypted, including the
generic username, password, synthetic email and client secret. The service uses
systemd credentials and private runtime copies; plaintext never enters the Nix
store. Imported members receive the native `account` client roles
`manage-account` and `view-profile` so they can manage their own password and
passkeys. The ordinary account has no administrator role. A separate permanent
administrator replaces Keycloak's temporary bootstrap account after its login
and permissions have been verified.

The [identity credential helper](../../hosts/nixos/desktop/local/homelab/credentials/identity_to_bitwarden.py)
generates missing bundles on first use and copies both password logins to
Bitwarden. Existing bundles are decrypted through SSH to their administrator
identity, without copying private keys. The helper preserves vault records and
refuses ambiguous matches or incompatible existing credentials. Supply freshly
evaluated `nixSeal.planFile` and `nixSeal.bootstrapPlanFile` paths, administrator
SSH destination, administrator identity and delegated-create key paths, and the
identity and wardrobe HTTPS origins. Its `--help` lists the arguments. Unlock
Bitwarden in an attended terminal before running it:

```sh
(umask 077; bw unlock --raw > "$XDG_RUNTIME_DIR/wardrowbe-bitwarden-session")
```

Pass that file as `--session-file`. It must be a private regular file owned by the
operator. The helper deletes it after both items sync successfully. On failure,
remove it when no longer needed. Credentials and the unlock token must never be
pasted into chat or entered as command arguments.

Prepare the matching signed nix-seal artifacts, then build and switch the host.
See the [secret preparation workflow](../secrets.md). Check `keycloak.service`,
`wardrowbe-migrate.service`, the backend/frontend and worker services, and
`ollama.service`. Open the wardrobe HTTPS site, choose SSO and use Bitwarden's
**Wardrowbe** item. Password sign-in requires no passkey enrollment.

After changing a login name or password, synchronize the existing vault items
with the deployed sealed credentials:

```sh
python hosts/nixos/desktop/local/homelab/credentials/homelab_to_bitwarden.py \
  --only Wardrowbe --only 'Wardrowbe sign-in administrator'
```

The importer updates matching items in place and preserves passkeys. It also
recognizes their former identity titles. Synchronize the Bitwarden browser
extension afterward so autofill uses the updated login. The ordinary entry
matches the Wardrowbe realm; the administrator entry matches the admin console.

To add a Bitwarden passkey later, open Keycloak's Account Console at
`https://identity.<HOMELAB_DOMAIN>/realms/homelab/account/`, select account
security and register a passkey. Use the identity host and realm from the
deployed configuration.
Approve Bitwarden's browser extension when prompted. Keycloak supports this
[optional account-console enrollment](https://www.keycloak.org/2025/09/passkeys-support-26-4).
The CLI does not create or store the passkey in nix-seal.

Realm imports [skip an existing realm at startup](https://www.keycloak.org/server/importExport).
Restarting or updating the package therefore preserves passwords, clients and
subsequently enrolled passkeys. The encrypted import is a bootstrap/recovery
input, not an ongoing password reset or realm-policy reconciliation mechanism.
A private completion marker under `/var/lib/keycloak-bootstrap` also prevents
repeated administrator provisioning from enforcing old bootstrap credentials.
The recovery inventory stops Keycloak and captures that marker alongside its
logical database export. Restore both from the same recovery point. For a new
empty database, remove the marker before bootstrap recovery.
Change an existing realm through its administrator console or supported API.
The ordinary login is dedicated to Wardrowbe. The **Wardrowbe sign-in
administrator** item manages its identity provider, rather than being a second
Wardrowbe application login. Additional services must use their own realms and
credentials instead of reusing Wardrowbe's account.

## Identity interface

Keycloak serves its native login pages and Account Console. Wardrowbe starts the
OIDC login flow from its own site; the Account Console manages the realm's
password, passkeys and sessions. Opening the identity host's root shows
Keycloak's upstream welcome page, not an application portal. Use the Account
Console URL above for account management and the separate `/admin/` path for
administration. The Actual realm has its own account and does not share the
Wardrowbe login. See [Keycloak's theme and Account Console guidance](https://www.keycloak.org/ui-customization/themes).

## State and resources

The module limits AI and image processing to one job each. The desktop uses local Gemma 3 4B for photos and text through Ollama, with Llama 3.2 3B available as a text option and a five-minute model idle period. The model is pulled by the NixOS Ollama loader after Wardrowbe credentials exist. The image worker uses local rembg. Its model cache and Numba cache are under `/var/cache/wardrowbe` and can be regenerated. The first background removal downloads the upstream U2Net model into that cache, so it needs network access and may take longer than later uploads. The model is not bundled in the Nix package because the release asset's license and provenance are [not yet explicit](https://github.com/danielgatis/rembg/issues/837).

A daily `wardrowbe-backup.timer` writes an atomic PostgreSQL custom-format dump to `/var/lib/wardrowbe-backup/latest.dump`. The desktop's daily file backup includes that dump. Wardrowbe's uploaded images are assigned to the attended cold backup, which stops writers before capture. Keycloak's PostgreSQL database is registered with the stopped-writer recovery workflow and must be captured with its realm credentials. Restore the database with `pg_restore` into an empty Wardrowbe database, then restore uploads from the same recovery point. The former Pocket ID state and encryption key are retained for recovery; the password-first deployment uses Keycloak instead.

The reusable module also registers Wardrowbe's state paths, PostgreSQL database, service writers and health endpoint with `homelab.operations`. Hosts that enable that recovery workflow can include the application in their stopped-writer export without recreating its inventory.

The backend and frontend listen only on loopback. The LAN proxy provides HTTPS and the existing LAN firewall policy. Application secrets are read at runtime, outside the Nix store. The backend uses PostgreSQL peer authentication over the local socket. Redis accepts only members of its Unix socket group, has no TCP listener, and has a 128 MiB memory cap with no eviction of queued jobs.

## Validation

Run `nix build --no-link .#wardrowbe-backend .#wardrowbe-frontend` in `pkgs/`, `nix build --no-link .#checks.x86_64-linux.configuration-wardrowbe` in `nix-homelab/`, then `just os-build desktop` at the root on the desktop. The first two verify package construction and module contracts; the full desktop build checks integration. After enrollment and activation, verify the health endpoint, OIDC login, one image upload, one AI suggestion, and a database export before considering recovery tested.

## AI providers and model selection

`services.wardrowbe.ai.provider` selects `ollama`, `openai`, `codex`, or a generic
`compatible` server. `textModel` and `visionModel` are independent defaults.
Wardrowbe's **Settings → AI endpoints → Test connection** discovers models for
per-user choices. Ollama capability metadata distinguishes text and vision
models; generic OpenAI catalogs do not guarantee image support. Select a model
whose provider documents image input for clothing analysis.

The desktop defaults to `gemma3:4b` for photos and text, and offers
`llama3.2:3b` as a selectable text option. Using one model for both default tasks
avoids weight reloads under the existing one-model limit. The native Ollama
loader pulls the configured models at activation; Nix does not build or embed
their weights. Idle unload keeps memory bounded. Selecting separate photo and
text models reloads weights when switching tasks. For all-Llama
inference, set `visionModel = "llama3.2-vision:11b"` and provision sufficient GPU
and host memory. Its 7.8 GB download is not its total runtime requirement.
[Ollama Llama vision catalog](https://ollama.com/library/llama3.2-vision).

### OpenAI API

```nix
services.wardrowbe.ai = {
  enable = true;
  provider = "openai";
  textModel = "<available-text-model-id>";
  visionModel = "<available-image-model-id>";
};
```

Add `AI_API_KEY` to the existing sealed runtime environment file. The module uses
`https://api.openai.com/v1` unless `baseUrl` is overridden. The package scopes this
credential to that configured endpoint and does not follow provider redirects.
Additional endpoints do not receive the default provider's secret. OpenAI API
billing and model access are separate from ChatGPT subscription access.
[OpenAI API authentication](https://developers.openai.com/api/reference/overview).

### ChatGPT OAuth through Codex

```nix
services.wardrowbe.ai = {
  enable = true;
  provider = "codex";
  textModel = "<available-codex-model-id>";
  visionModel = "<available-codex-image-model-id>";
  codex.allowedModels = [ "<available-codex-model-id>" "<available-codex-image-model-id>" ];
};
```

To keep local inference as the default while offering OAuth in Settings, retain
`provider = "ollama"` and enable only `ai.codex.enable = true` with an explicit
`ai.codex.allowedModels` list. Wardrowbe Settings discovers the adapter address
from the server configuration. Both providers can run together; the default determines
which endpoint gets the runtime API key.

Leave `ai.codex.allowedModels` empty to discover every visible text-capable model
from the signed-in account's refreshed Codex catalog. An explicit list remains
available for installations that need a restriction. The adapter caches the
catalog for five minutes and validates model identifiers and input capabilities.
It disables tools in the temporary catalog used for each completion. Inspect the
same catalog with `codex debug models` in the service's signed-in environment.
The offline `--bundled` snapshot may omit newly released models.

Choose **Use automatic model selection** in Wardrowbe Settings to save the
`auto-value` policy for both photos and text. This is a stable policy identifier,
not an OpenAI model name. Each request resolves it against the current discovered
models. Provider descriptions identify balanced models for outfit constraints
and efficient image models for garment tagging. The policy prefers current,
general-purpose models over older or specialized models, then uses the provider's
catalog order. It contains no model-version list or fixed price table. Manual
model choices remain available and are validated against the refreshed catalog.

Settings show the currently resolved models, refresh time and selection reason.
This is a value heuristic, not measured garment accuracy or a guarantee of the
lowest cost. Codex does not expose exact subscription pricing in this catalog.
OAuth uses ChatGPT plan limits and credits; API token prices do not describe
the cost of subscription usage. See the official [catalog discovery documentation](https://learn.chatgpt.com/docs/app-server)
and [API pricing](https://developers.openai.com/api/docs/pricing).
Catalog presence also does not guarantee account entitlement. A disappeared
manual model is rejected; automatic choices follow the refreshed catalog.
`codex.package` can select another compatible CLI build.

After activating the configuration, open **Settings → AI Endpoints → OpenAI
account** in a browser on the desktop hosting Wardrowbe. The default uses normal
browser OAuth. Choose **Connect OpenAI**, then **Open OpenAI sign-in**. Sign in on
OpenAI's website and return to Settings, which polls for completion. No device-code
permission or terminal command is needed. Codex owns the loopback callback, PKCE,
state verification and token exchange. Its authorization URL stays unchanged.

A browser on another computer or phone cannot reach the service's localhost
callback. Select **On another computer or phone** explicitly to use device codes.
That option requires enabling device-code sign-in in ChatGPT **Settings → Security**;
managed accounts may require administrator permission. Only enter a code initiated
in Wardrowbe on OpenAI's official website. Never share codes or approve one someone
sends you. **Restart sign-in** cancels the old attempt before obtaining a new one.
Wardrowbe does not automatically fall back to device codes or bypass provider
permissions. Browser OAuth avoids the separate device-code approval mechanism,
but still requires checking the provider's website before signing in.
[Official Codex authentication](https://learn.chatgpt.com/docs/auth),
[app-server authentication](https://learn.chatgpt.com/docs/app-server), and
[device-code phishing considerations](https://www.rfc-editor.org/rfc/rfc8628.html#section-5.4).

Choose separate photo-analysis and outfit models, then select **Use OpenAI for
my wardrobe**. This immediately saves the endpoint first in the signed-in user's
preferences. Other enabled endpoints and the server default remain fallbacks.
Model access still depends on the account, even when an ID is in the administrator's
allowlist. Disconnect or cancel sign-in from the same Settings section. A later
connection can reuse the saved model selection. The terminal helper remains
available for administrative recovery.

The OpenAI account is installation-wide. The first Wardrowbe user to start
browser setup owns its management; their UUID is recorded privately, without
hardcoding a login name. Other users cannot replace or disconnect that account
through Settings. The binding survives logout and restoration of the credential
directory. Administrators can reset the private `browser-owner` binding for an
explicit ownership transfer. The management API is only on a Unix socket within
a directory accessible to the Wardrowbe service group; browser requests pass
through Wardrowbe's normal authenticated API. No OAuth access or refresh tokens
are returned to Settings. No login or paid inference is part of a Nix build.

### Where AI is used

| Feature | Model and input |
| --- | --- |
| Clothing photo analysis and reanalysis | Vision model; clothing photograph; produces clothing type, colors and other tags |
| Outfit recommendations | Text model; wardrobe details, style preferences and weather context |
| Clothing pairings | Text model; clothing details and pairing preferences |
| Scheduled outfit notifications | The same recommendation service and saved user preferences |
| Background removal | Separate local image model, independent of OpenAI selection |

Inventory, calendars and wear tracking do not require OpenAI. Style-learning
insights are computed from feedback using application rules. Both queued photo
analysis and outfit/pairing requests load saved user AI endpoints; changing the
selection affects new work. Photos and outfit context leave the host when the
selected endpoint is OpenAI. Ollama inference stays local.

Codex owns OAuth refresh in `/var/lib/wardrowbe-codex` with mode 0700. Wardrowbe
cannot read that directory. It is intentionally excluded from wardrobe backups;
repeat login after restoring the service. The adapter accepts embedded images
and non-streaming completions, with request, concurrency and duration limits.
It disables shell, image-file tools, apps, plugins, hooks, subagents and search;
its static catalog also removes the file-editing and experimental model tools.
Each request has an empty temporary workspace, custom wardrobe instructions,
read-only sandbox, and ephemeral session. Raw CLI output is suppressed.

This is a translation of Wardrowbe's request subset, not the complete OpenAI
API. Sampling parameters, log probabilities and exact token limits are not
implemented by this CLI transport. OAuth permits models supported by Codex and
the signed-in account, rather than every OpenAI API model. API-key access remains
the documented default for unattended OpenAI automation.
[Codex noninteractive operation](https://learn.chatgpt.com/docs/non-interactive-mode).

All local AI listeners stay on loopback. Local host users can invoke these
listeners, as with the existing Ollama service; do not expose the adapter through
the LAN proxy. Clothing photos and prompts leave the host when using OpenAI or
Codex, whereas the Ollama inference path is local.

## Wardrobe planning

The paired packages include garment reviews, repair and replacement decisions,
lifestyle and laundry coverage, and exact purchase comparisons. Open **Wardrobe
planning** from navigation or a garment's detail view. Follow the
[planning guide](wardrowbe-planning.md) to record evidence and define needs.
Planning records are included in the existing PostgreSQL database backup. Basic
audits work without AI; optional drafts use entered text and saved model settings.
