# macOS configuration

The Mac configuration has two owners. The nix-darwin `macos` module owns
machine policy and typed user defaults. The Home Manager `macos` module owns
packages and user commands that depend on the Home Manager generation.

Apply the combined configuration with `darwin-rebuild`. A standalone Home
Manager switch cannot apply Software Update policy or the typed system
defaults.

## Preferences

`macos.preferences` is the nix-darwin interface. Its defaults provide immediate
screen locking, automatic macOS updates, keyboard navigation, a development
oriented Finder, tap-to-click, two-finger secondary click, safe Safari download
handling, and a conventional screenshot directory.

`motion` accepts:

- `normal`, which leaves Reduce Motion and animation timings alone;
- `reduced`, which uses Apple's supported Reduce Motion preference;
- `instant`, which enables Reduce Motion and sets every current typed
  nix-darwin animation timing to its minimum or disabled value.

Apple does not expose a zero-duration native Spaces transition. Reduce Motion
changes the horizontal slide to Apple's reduced presentation, which may still
be a short cross-fade. The optional `instantPrivateDefaults` setting also
disables Finder animations and current Dock app-launcher transitions through
private defaults. Check those private settings after every major macOS update.
For genuinely instant workspace switching, use AeroSpace workspaces instead of
native Spaces.

`customUserPreferences` and `customSystemPreferences` are escape hatches for
settings that nix-darwin does not type. Keep them small. A typed option is
preferable because it validates values and records which process owns the
preference.

Each activation removes obsolete defaults formerly written by the Home
Manager preference files. Removing a default from Nix does not remove it from
the macOS preference database, which is why this cleanup is explicit.

## Commands

`macos.commandProfile = "native-first"` keeps the macOS command behavior for
shared names such as `ls`, `sed`, and `tar`. GNU packages remain installed.
Common GNU commands have explicit names such as `gls`, `gsed`, `gstat`, and
`gtar`. Use `gnu-first` only for a shell environment whose scripts assume GNU
behavior for unprefixed commands.

## Applications

`macos.applications` keeps copied Home Manager apps as the canonical Launch
Services registrations. It runs after `copyApps` and before launch agents start.
It unregisters competing top-level Nix-store bundles with the same identifiers,
preserves unrelated installations, and archives confirmed legacy store symlinks
with a recovery journal under
`$XDG_STATE_HOME/macos-applications/recovery.noindex/`.

The `chatgpt` command opens the copied app through Launch Services, reusing its
running instance. The `code` command executes the copied bundle's original CLI,
preserving arguments, remote-terminal IPC, exit status, and `--wait`. AeroSpace's
launch agent also starts its copied bundle; its separate IPC CLI stays unchanged.
The ChatGPT wrapper matches the package's command spelling so it replaces the
original on case-insensitive stores; lowercase access is retained on both kinds
of filesystem.

Run `hm-macos-applications --check` to verify registrations or add `--dry-run`
to preview repairs without modifying state. A plain invocation reconciles them.
macOS may retain unregistered store paths as launch-disabled records; these are
excluded only when the native registry explicitly marks them disabled. The
command does not reset Spotlight or the Launch Services database.

Spotlight Settings shortcuts are separate from app installations. Use
Command-Space, then Command-1 for Applications browse mode. Showing `.app`
extensions does not establish that a result is a duplicate. See the
[investigation and native validation](../../../docs/research/macos-spotlight-applications-research.md).

## Dock

`macos.dockItems.mode` controls reconciliation:

- `authoritative` repairs changes made outside Nix;
- `initialize` applies a changed Nix layout once and then permits manual edits.

The authoritative mode compares a normalized view of the current Dock with the
last applied state. It ignores volatile plist fields, validates every target,
and checks that `dockutil` can read the Dock before removing anything. Dry runs
print every planned command and do not read, write, or create cache files.

## Finder favorites

`macos.finderFavorites` installs the source-built, arm64-native
`finder-favorites` tool and writes a versioned JSON configuration. Managed
favorites form a block at the top or bottom; unlisted favorites are never
deleted and retain their relative order. Identity is based on canonical paths,
so duplicate display labels are safe.

The mode can be `manual`, `initialize`, or `reconcile`. Manual mode does not
write Finder state. Initialize mode applies once and leaves later changes
alone. Reconcile mode repairs drift during each Home Manager activation. Both
writing modes require `allowDeprecatedBackend = true` because Apple provides no
supported API and has deprecated the remaining `LSSharedFileList` interface.

The tool rejects root, avoids network-volume mounting and interactive
resolution, locks concurrent invocations, journals each transaction, rolls
back failed writes, and verifies the final snapshot. Tests use an in-memory
adapter and never access the live sidebar. If Apple removes the backend, switch
the module to manual mode and drag the generated directories into Finder.

## OCR capture

`macos.ocrCapture` installs the all-Swift `pkgs.ocr-capture` application from
`nixpkgs-personal` and launches its stable copied app bundle from AeroSpace.
The only desktop action is region OCR. It delegates the complete selection to
macOS's built-in Screenshot service, recognizes the clipboard image locally
with Vision, replaces it with plain text, and exits. There is no custom overlay,
cursor, HUD, notification, review window, history, speech, or clipboard expiry.

The module configures accurate, fast, or adaptive recognition; languages and
custom words; raw, lines, paragraph, code, table, and Markdown rendering; image
bounds; and a recognition timeout. macOS controls the cursor, coordinates,
selection behavior, permission interface, cancellation, and capture sound.

Public Nix builds are ad-hoc signed; set `signingIdentity` to a local Apple
Development or Developer ID identity to re-sign the copied app without placing
a private key in the Nix store.

## Application capability readiness

`macos.applicationCapabilities` composes feature-specific requirements from the
selected application modules. `hm-macos-readiness --check` verifies bundle
identity and reports permission state conservatively, without prompts or writes.
Explicit `--guide` and `--verify` modes support attended GUI feature tests and
private historical receipts. See the [runbook](../../../docs/operations/darwin-application-readiness.md)
for optional feature selection, exit codes, signing repairs and validation limits.
