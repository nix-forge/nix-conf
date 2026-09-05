# Modern Finder favorites on Apple silicon

Research date: 2026-09-02

## Decision

Keep `macos.finderFavorites` disabled on the M4 Mac until its backend changes.
The module's Intel-only warning is correct about the executable that Nixpkgs
installs. The Nix package search result is not saying that the executable is
native on every Mac. Its Darwin platform metadata says where Nix may evaluate
the derivation, while the derivation downloads a 2016 package containing one
unsigned `x86_64` executable. On the current unstable channel that metadata
even expands to `aarch64-darwin`, so this is a Nixpkgs packaging bug rather than
a contradiction in the local configuration.

There are two useful paths forward, because the interactive and declarative
jobs have different best answers.

1. Package SidebarFavorites 1.2.2 in `nixpkgs-personal` as an opt-in graphical
   application. It is the best current user-facing tool I found. The release is
   native on Apple silicon, Developer ID signed, notarized, and stapled. It has
   a thoughtful native interface and tracks whether it created or merely
   adopted each Finder row. It is suitable for deliberate, interactive edits.
2. Build a small Swift core and CLI for declarative Home Manager reconciliation.
   Use a narrow Objective-C bridge around `LSSharedFileList`, default to
   additive changes, and identify rows by URL and item ID rather than display
   name. Add a SwiftUI application only after the core has passed destructive
   integration tests on disposable macOS accounts.

Both choices still depend on an Apple API deprecated since OS X 10.11. There is
no honest way to promise both automatic Finder-favorites management and a
supported Apple API today. The application and module must say this plainly,
gate writes by tested macOS version, and retain a manual fallback.

Do not build the replacement around Rust, direct `.sfl3` or `.sfl4` file edits,
Finder Sync, File Provider, or UI automation. Rust can call the same C API, but
it adds a second foreign-function layer before the code reaches AppKit,
Foundation, and SwiftUI. It buys no safer Finder backend. Swift keeps almost all
code memory safe and confines the deprecated Core Foundation calls to one small
Objective-C file. Swift's Apple-platform SDK overlays are specifically designed
to map Objective-C frameworks into Swift, and Swift checks initialization,
bounds, lifetimes, and conflicting memory access in ordinary code.
[Swift SDK overlays](https://www.swift.org/documentation/standard-library/)
[Swift memory safety](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/memorysafety/)

## What the Nix package actually contains

The root flake pins Nixpkgs 26.11pre at `9fbb54b3`. Its expression does not
build `mysides`. It fetches
`mysides-1.0.1.pkg`, unpacks it, and copies its executable. Its only platform
restriction is `lib.platforms.darwin`.
[Pinned Nixpkgs package](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/pkgs/by-name/my/mysides/package.nix#L1-L47)

Read-only inspection on this host produced:

```console
$ nix eval --json nixpkgs#mysides.meta.platforms
["aarch64-darwin"]

$ file "$(nix build --no-link --print-out-paths nixpkgs#mysides)/bin/mysides"
Mach-O 64-bit executable x86_64

$ codesign -dvvv "$(nix build --no-link --print-out-paths nixpkgs#mysides)/bin/mysides"
code object is not signed at all
```

The binary has a macOS 10.9 deployment target and was linked against the 10.12
SDK. It runs on this Apple silicon Mac only because Rosetta is installed. Apple
recommends a native `arm64` slice, or a universal binary when Intel support is
also required.
[Apple silicon binary guidance](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary)

The architecture defect is fixable in isolation. Compiling the original
Objective-C source with the current SDK produced a thin `arm64` binary. That is
not a reason to keep the program. Version 1.0.1 was published on 2016-09-26,
the last repository commit was in January 2019, and the implementation is a
thin wrapper around deprecated calls.
[Version 1.0.1 release](https://github.com/mosen/mysides/releases/tag/v1.0.1)
[Upstream history](https://github.com/mosen/mysides/commits/master/)

The old source also has defects that matter to automation. `remove` reads
`argv[2]` without first proving it exists, deletion selects the first matching
display name, insertions ignore the returned item and any failure, and list
formatting performs unsafe Core Foundation ownership conversions.
[Original command implementation](https://github.com/mosen/mysides/blob/71549753766ef14b3ba8c139ac8cac61c644eff7/src/main.m#L45-L177)
Recompiling it for ARM would remove Rosetta from the path while preserving the
more important reliability problems.

## Apple's supported boundary

Apple's current SDK still declares `kLSSharedFileListFavoriteItems` and the
read, insert, move, property, and remove functions. Every relevant declaration
is annotated `API_DEPRECATED("No longer supported", macos(10.5, 10.11))`.
Apple does not name a replacement for Finder Favorites.
[Apple's deprecated Launch Services symbols](https://developer.apple.com/documentation/coreservices/launch_services/deprecated_symbols)
[Apple's Carbon Core function index](https://developer.apple.com/documentation/coreservices/carbon_core/carbon_core_functions)

Local inspection used macOS 26.6.2 on an M4, Xcode 26.6, Swift 6.3.3, and the
macOS 26.5 SDK. The deprecated symbols are present. A source-built ARM Swift
port listed the live favorites without Full Disk Access in 0.01 seconds with a
9 MB maximum resident set. The old Intel binary returned the same list through
Rosetta, and `sysctl.proc_translated` reported `1` inside its `x86_64` process.
This proves the read path on one current host. It does not prove that writes
work on every 26.x release or that Apple will retain the service.

Finder's own AppleScript dictionary offers `sidebar width` and the Sidebar
preferences pane, but no command or object for favorite rows. The built-in
`sfltool` is Apple-signed with private shared-file-list entitlements, including
read-only access to arbitrary shared lists. A third-party replacement cannot
copy those entitlements.

The public command set confirms the limit. On this host `/usr/bin/sfltool`
offers `csinfo`, `dumpbtm`, `archive`, `clear`, `resetbtm`, `resetlist`, `list`, and
`list-info`. The old `add-item` command is gone. Even `mysides` documents that
Apple removed the useful `sfltool` mutation commands after macOS 10.12.
[Upstream `mysides` note](https://github.com/mosen/mysides/blob/355d010b61c4ad36fcdd84b0f9e6ec530369bd1b/README.md#L5-L13)

Finder Sync is not a general escape hatch. Apple says it exists so file-sync
clients can badge monitored folders and add contextual or toolbar commands.
Apple also says it is not intended as a general tool for modifying Finder's
interface. A user may drag a monitored root into the sidebar, but the extension
does not manage arbitrary favorites.
[Apple Finder Sync guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html)

File Provider is also the wrong abstraction. A File Provider domain represents
content managed by an application, normally an account or remote storage
location. The extension must enumerate, fetch, materialize, and synchronize
that content. Creating a provider merely to make existing local folders appear
in Finder would relocate ownership and add an entire storage implementation to
a sidebar preference.
[Apple File Provider documentation](https://developer.apple.com/documentation/fileprovider)
[Replicated File Provider extension](https://developer.apple.com/documentation/fileprovider/replicated-file-provider-extension)

UI automation is technically possible and a poor default. It would need to
drive Finder menus or drag rows through Accessibility and Apple Events. Apple
requires explicit user authorization and warns that an Accessibility app can
control the Mac and access documents and data. A sandboxed app also needs an
Apple Events usage description and entitlement.
[Apple Accessibility permission](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/26/mac/26)
[Apple Events usage description](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)
[Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)

The only fully supported fallback is manual. Apple documents dragging a folder
or disk into Favorites, Command-dragging a file or application, dragging rows
to reorder them, and dragging a row out to remove it.
[Apple Finder sidebar guide](https://support.apple.com/guide/mac-help/customize-the-finder-sidebar-on-mac-mchl83c9e8b8/mac)

## Existing tools

### SidebarFavorites 1.2.2

SidebarFavorites is the strongest existing GUI. Version 1.2.2 was released on
2026-08-02 and requires macOS 13 or later. It is a native SwiftUI and AppKit
application for adding favorites and assigning SF Symbols or custom SVG icons.
It handles local folders, cloud-provider folders, mounted disks, and network
shares. It does not need a resident background service for its normal mode.
[SidebarFavorites 1.2.2](https://github.com/ivg-design/SidebarFavorites/releases/tag/v1.2.2)
[Feature and mechanism documentation](https://github.com/ivg-design/SidebarFavorites/blob/31af798c93c704963a845c23e8b7f9aedfdf3756/README.md)

Its engineering is substantially better than `mysides`:

- The Objective-C bridge is the only component allowed to call
  `LSSharedFileList`. It uses SDK declarations rather than `dlsym`, keeps list
  snapshots alive while item references are in use, resolves without mounting
  volumes or showing UI, and reports structured errors.
  [SFL bridge contract](https://github.com/ivg-design/SidebarFavorites/blob/31af798c93c704963a845c23e8b7f9aedfdf3756/SidebarFavoritesManager/Services/SFLBridge.h)
  [SFL bridge implementation](https://github.com/ivg-design/SidebarFavorites/blob/31af798c93c704963a845c23e8b7f9aedfdf3756/SidebarFavoritesManager/Services/SFLBridge.m)
- It records a persistent item ID and whether the row was created by the app or
  adopted from the user. Removing an adopted favorite restores its normal icon
  but keeps the row. That ownership rule is exactly what a declarative tool
  needs.
  [Reconciliation ownership logic](https://github.com/ivg-design/SidebarFavorites/blob/31af798c93c704963a845c23e8b7f9aedfdf3756/SidebarFavoritesManager/Services/FavoriteSyncCoordinator.swift)
- It serializes its own reconciliation, writes JSON configuration atomically,
  backs up corrupt configuration instead of overwriting it, and asks before a
  migration changes existing state.
  [Configuration persistence](https://github.com/ivg-design/SidebarFavorites/blob/31af798c93c704963a845c23e8b7f9aedfdf3756/SidebarFavoritesManager/Services/ConfigManager.swift#L61-L139)
- Its release DMG contains a universal main executable. Local verification
  found a valid Developer ID signature, hardened runtime, a stapled notarization
  ticket, and a passing Gatekeeper assessment.

There are reasons not to adopt it as the Home Manager backend. It has no CLI or
declarative plan interface, does not expose ordered reconciliation, and appears
to have no automated test target. Its icon feature uses a private per-row
property and a private CoreUI writer. The optional mode that preserves both a
folder icon and sidebar icon generates one Finder Sync extension per favorite.
Those mechanisms add much more version-sensitive code than this repository
needs. It also makes one GitHub release API request at each launch.
[Update checker](https://github.com/ivg-design/SidebarFavorites/blob/31af798c93c704963a845c23e8b7f9aedfdf3756/SidebarFavoritesManager/Services/UpdateChecker.swift#L1-L53)

Package it if the native GUI and custom icons are wanted. Keep it independent
of `macos.finderFavorites`; do not edit its private `config.json` from Nix.
Upstream already supplies a binary Nix expression that preserves the signed
application by disabling fixups.
[Upstream Nix package](https://github.com/ivg-design/SidebarFavorites/blob/31af798c93c704963a845c23e8b7f9aedfdf3756/nix/default.nix)
For this repository, mark the package `aarch64-darwin` initially. The main app
is universal, but the release's embedded Finder Sync template executables are
thin `arm64`, so its complete optional feature set is not actually universal.

### The 2026 Swift ports

`jeremy4971/mysides-swift` is a useful compatibility proof. Its single source
commit builds a native ARM CLI, and its signed installer is notarized. The
source-built executable successfully listed this host's favorites. It still
wraps `LSSharedFileList`, sets macOS 26 as its deployment target, and says it
requires 26.1 or newer.
[Swift port source](https://github.com/jeremy4971/mysides-swift/tree/5de8d5cb5b7a788601df6f581b1bbf86edece80b)
[Version 1.0.1 release](https://github.com/jeremy4971/mysides-swift/releases/tag/v1.0.1)

It should not become the production backend unchanged. Insertion finds the C
symbol with `dlsym` and converts it using `unsafeBitCast`; missing symbols call
`fatalError`. Add and insert ignore the returned result. URL parsing accepts
values that are not `file` URLs. Most seriously, its three integration tests
operate on the logged-in user's live list, and `removeAll` erases every
favorite.
[Dynamic insertion bridge](https://github.com/jeremy4971/mysides-swift/blob/5de8d5cb5b7a788601df6f581b1bbf86edece80b/Sources/mysides/SidebarFileList.swift#L1-L78)
[Destructive test](https://github.com/jeremy4971/mysides-swift/blob/5de8d5cb5b7a788601df6f581b1bbf86edece80b/Tests/mysidesTests/SidebarFileListTests.swift#L1-L22)

The August 2026 `seakrebel/mysides-swift` fork adds better argument errors,
unit tests, and glyph support, but has no release and still rests on the same
deprecated API. Its icon command adds a generated helper bundle and another
private property. It is prior art, not a dependency to adopt.
[Fork source](https://github.com/seakrebel/mysides-swift/tree/c281bb6df06667dff5333ec58705d33730457a44)

### Direct file editors

`fabienconus/sidebar-editor` reads and rewrites
`com.apple.LSSharedFileList.FavoriteItems.sfl3`, or `.sfl4` on macOS 26. It
requests Full Disk Access, decodes Apple's private archive, writes it back
without atomic replacement, and restarts `sharedfilelistd` or Finder. Its own
README says the method is unsupported and may break at any time.
[Sidebar editor warning](https://github.com/fabienconus/sidebar-editor/blob/e09de33f421a9313c8b0a12d74f935cd666cafab/README.md#L3-L28)
[Private archive implementation](https://github.com/fabienconus/sidebar-editor/blob/e09de33f421a9313c8b0a12d74f935cd666cafab/sbedit/main.swift#L393-L500)

This is worse than using the deprecated service API. It depends on file names,
archive schema, cache behavior, and daemon lifecycle, while also asking for a
broad privacy grant. A malformed or interrupted write could damage the whole
sidebar. Do not use this design as a fallback.

`robperc/FinderSidebarEditor` remains a Python and PyObjC wrapper around
`LSSharedFileList`. Its March 2025 update replaced one deprecated resolver with
another because the first stopped working. That change is a compact example of
the compatibility churn a maintained replacement must expect.
[FinderSidebarEditor source](https://github.com/robperc/FinderSidebarEditor/tree/65567c0ab2fd3a00ff99d4a1bc791239ac914c23)

## Proposed product

Use one repository and one domain model with two front ends:

```text
Home Manager JSON ----+
                      |
CLI ----------------> planner ----> mutation journal ----> backend protocol
                      ^                                      |
SwiftUI app ----------+                                      v
                                              Objective-C SFL bridge
                                                          |
                                                          v
                                               sharedfilelistd / Finder
```

The planner and policy code must not import CoreServices. It consumes a current
snapshot and a desired document, then returns an ordered plan. The CLI prints
or applies that plan. The GUI renders the same plan and adds confirmations and
undo. A backend protocol lets unit tests use an in-memory list. Only the bridge
knows about `LSSharedFileListRef`, item lifetimes, raw flags, or deprecation
suppression.

Use a versioned JSON desired-state document because Nix generates JSON without
another serializer dependency. Keep runtime ownership state in the user's
Application Support directory, not in the Nix store. A first schema can contain:

```json
{
  "schemaVersion": 1,
  "mode": "additive",
  "entries": [
    {
      "id": "projects",
      "path": "/Users/example/Developer",
      "label": "Developer",
      "position": 4,
      "onMissing": "error"
    }
  ]
}
```

`id` is a stable configuration key, not Finder identity. The runtime binding
stores the Finder item ID, last resolved canonical URL, whether the program
created the row, and the last verified operation. Never use a display label as
the primary key. Duplicate labels are legal and common enough to handle.

The initial application should target `arm64` and macOS 26.1 or newer. Expand
the compatibility declaration only after write tests pass on each older or
newer release. A universal release is optional. This repository's active Mac
does not justify doubling testing and package complexity for Intel.

## Functional requirements

The first production release needs these behaviors:

- `list` returns ordered items with item ID, display name, resolved URL, missing
  status, and ownership. `--json` has a versioned schema. Human output escapes
  control characters.
- `plan --config FILE` computes the exact changes without writing. `apply`
  consumes the same schema, prints the plan in dry-run mode, and verifies the
  final snapshot.
- `add`, `remove`, and `move` accept a path, stable configuration ID, or exact
  item ID. They do not silently fall back to display-name matching.
- `export` writes a logical JSON snapshot. `import` previews its plan. The tool
  must state that public APIs cannot preserve every private Finder row property.
- `doctor` reports architecture, macOS version, symbol availability, snapshot
  capability, list seed, and whether the active backend is supported by this
  release. An explicit `doctor --write-test` may create and remove one uniquely
  named temporary row after confirmation. Read access alone cannot prove that
  mutations work.
- Additive mode creates and orders configured rows while preserving unrelated
  rows. It is the default. Authoritative mode may prune only rows that the tool
  previously recorded as managed.
- Deleting adopted or unknown rows requires a separate flag and confirmation.
  There is no magic `remove all` name. Bulk deletion requires `--yes` in a
  noninteractive invocation and still writes a journal first.
- Path input accepts absolute local file URLs. Resolve `~` before the core sees
  it. Reject relative paths, NULs, control characters, credentials in URLs, and
  remote schemes by default. Already mounted paths under `/Volumes` are ordinary
  file URLs. Favorite-server management is a separate future feature.
- Resolution always uses the no-interaction and do-not-mount flags. A sidebar
  check must never mount a network share or show a credential prompt.
- Each apply takes a fresh snapshot and seed, computes a minimal diff, checks
  the seed again before the first write, and replans if Finder or the user has
  changed the list. The process serializes its own writes with a per-user lock.
- After every mutation, take another snapshot and verify the intended row,
  position, and ownership. Treat an ignored return value as a bug.
- Record inverse operations before each write. On failure, stop and attempt the
  verified inverse sequence. Never claim a complete rollback for special or
  unresolved rows that the public API cannot reconstruct.
- Missing paths follow explicit policy: `error`, `skip`, or `create-directory`.
  Creation must be opt-in, limited to the user's home by default, and use fixed
  permissions without following a hostile symlink chain.
- Running as root or through `sudo` is an error. Favorites belong to the
  graphical user. No helper daemon, privileged tool, launch agent, or login item
  is needed.

The Home Manager module should expose `manual`, `initialize`, and `reconcile`
modes. `manual` installs the tool and supplies check commands. `initialize`
applies one desired-state revision and then leaves later user changes alone.
`reconcile` repairs drift after each Home Manager switch. Activation must use
Home Manager's dry-run-aware `run` helper and should default to warning on an
unsupported OS rather than failing an unrelated home switch.

## UI and accessibility requirements

The GUI should remain an on-demand application. A menu-bar resident process is
not justified for a setting changed occasionally.

- Use a native SwiftUI window with AppKit where SwiftUI lacks a precise API.
  Show live Finder rows and desired rows in one ordered list. Clearly mark
  managed, adopted, missing, ambiguous, and pending entries.
- Add folders through `NSOpenPanel`, drag and drop, and a path field. Support
  drag reordering, plus Move Up and Move Down commands for keyboard and VoiceOver
  users.
- Put Apply, Undo Last Apply, Export, Import, and Diagnose in standard menus as
  well as visible controls. Every icon-only button needs a label and help text.
- Show the planned insertions, moves, and removals before a destructive apply.
  Name the exact rows that remain untouched. Never restart Finder automatically.
- If the backend is unavailable, disable Apply without hiding the cause. Offer
  to reveal each directory in Finder and show Apple's drag-to-Favorites steps.
- Respect Reduce Motion, system accent color, light and dark appearances,
  Dynamic Type where available on macOS, full keyboard access, VoiceOver, and
  high contrast. Test at all three Finder sidebar icon sizes.
- Keep labels short and use monochrome SF Symbols in the application's own
  sidebar. Apple recommends familiar symbols, user-controlled ordering, and the
  normal accent color for macOS sidebars.
  [Apple sidebar design guidance](https://developer.apple.com/design/human-interface-guidelines/sidebars)
  [Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility)

Custom Finder glyphs should not be a version-one requirement. SidebarFavorites
already does that job. Adding private icon properties, an SVG parser, CoreUI
catalog generation, and optional Finder Sync helpers would multiply the attack
and compatibility work without improving declarative favorites management.

## Security requirements

The useful security boundary is small enough to enforce:

- Run as the current user with no entitlements, Full Disk Access, Accessibility,
  Automation, or administrator authorization. Make no network requests. Nix
  owns updates.
- Do not read file contents. The program needs path metadata and the Finder list,
  not the contents of a favorite directory.
- Never open or rewrite `.sfl` archives. Let Apple's service own persistence and
  caching.
- Use argument arrays and framework calls. Do not invoke a shell. If a system
  process such as Finder must be opened for the manual fallback, call a fixed
  system API rather than a configurable executable.
- Bound JSON size, item count, label length, and path length. Reject unknown
  schema versions. Encode state atomically and create its directory as mode
  `0700`; create state and journals as `0600` because project names and paths can
  reveal private work.
- Escape terminal control sequences in diagnostics and human list output. Never
  include credentials from a URI in logs, plans, or a world-readable Nix store
  path.
- Keep third-party dependencies to zero if the CLI remains small. If Swift
  Argument Parser is adopted for completions and polished help, pin its exact
  source and lock file and vendor it for offline Nix builds.
- Compile Swift in Swift 6 language mode with complete strict concurrency and
  warnings as errors. Keep the Objective-C bridge below roughly 500 reviewable
  lines and enable Clang's static analyzer and warnings as errors there.
- Treat backend availability as data, not a crash. Never use `fatalError`,
  `unsafeBitCast`, or dynamic symbol lookup for a missing optional feature.

App Sandbox reduces damage from an exploited GUI, but Apple lists modifying
other applications' preferences and terminating other applications among
incompatible activities. The first prototype must prove that
`LSSharedFileList` read and write behavior works from a sandboxed app before the
product promises sandboxing. If it does not, distribute outside the Mac App
Store as a narrow unsandboxed app with no extra entitlements. Do not compensate
with temporary sandbox exceptions.
[Apple App Sandbox restrictions](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)

For direct distribution, sign every executable with Developer ID, enable the
hardened runtime without exception entitlements, use a secure timestamp,
notarize the app or package, and staple the ticket. Apple requires those pieces
for its notarization workflow.
[Apple notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

Nix source builds cannot contain a private Developer ID key. Ad hoc sign the
Nix-built bundle with hardened runtime, or apply an optional local signing
identity after copying the application out of the store. The CLI should not
need a TCC permission, so its correctness must not depend on a persistent code
identity. A separately downloaded release should use Developer ID and
notarization.

## Performance and reliability targets

This is a small list and should behave like one:

- `list` and a no-op `plan` should finish within 100 ms at the 95th percentile
  on the M4 host with 100 favorites. A no-op apply should perform no writes.
- A normal five-item apply should finish within 500 ms, excluding Finder's own
  visual refresh. No command may wait for a volume mount.
- Idle GUI CPU should round to zero and memory should stay below 75 MB after the
  symbol catalog and views settle. No polling timer is needed.
- Planner complexity should be linear or `O(n log n)`. Do not optimize the
  private API bridge before measurements, but never rescan the list once per
  desired item.
- Cancellation before the first write is clean. Cancellation during apply
  completes or reverses the current operation before returning.
- A crash, forced quit, concurrent Finder edit, stale bookmark, or missing
  volume must not remove an unrelated row. The next run detects an unfinished
  journal and offers verified recovery.

These are release gates, not marketing claims. Record benchmark fixtures and
run them on the supported low-end Apple silicon runner as well as the M4.

## Test strategy

Most tests must never touch a real sidebar:

- Unit-test parsing, normalization, identity, diffing, ordering, ownership,
  journal recovery, exit codes, and JSON schema against an in-memory backend.
- Add property tests for idempotency, preservation of unmanaged rows, duplicate
  labels, Unicode normalization, symlink spellings, stale URLs, and every
  permutation of a small list.
- Fuzz the JSON decoder and CLI parser with size limits enabled. Run malformed
  output through terminal-control escaping tests.
- Test the Objective-C bridge under Address Sanitizer. Test the Swift planner
  and UI state under Address Sanitizer and Thread Sanitizer in separate jobs.
  Enable Swift strict concurrency in every build.
- Put integration tests in a separate executable that refuses to run unless an
  explicit environment flag and disposable-account marker are both present.
  Snapshot the test account's list, add uniquely identified fixtures, exercise
  add, move, remove, stale paths, conflicts, and rollback, then restore and
  verify the snapshot in `defer` cleanup.
- Never run mutation tests in `nix build` under the developer's login. The 2026
  Swift port's `removeAll` test is the example to avoid.
- Run the integration suite on clean macOS virtual machines for 26.1, the latest
  26.x point release, and the next macOS beta. Test `arm64` first. Add Intel only
  if the project chooses to support it.
- Use XCUITest for keyboard-only add, reorder, plan, cancel, apply, undo, missing
  backend, and VoiceOver labels. Perform a manual VoiceOver and high-contrast
  release check because automated identifiers do not prove usability.
- After each macOS update, run a read-only production smoke test first. Run the
  confirmed temporary write test only in the disposable account. Update a
  checked-in compatibility matrix with OS build, SDK, backend results, and any
  Finder refresh behavior.

## Packaging plan

### Immediate GUI package

Add `pkgs/by-name/si/sidebarfavorites` to `nixpkgs-personal`, based on the
upstream expression. Pin version 1.2.2 and the DMG hash, use `_7zz` to unpack,
copy the complete app bundle, set `dontFixup = true`, declare
`sourceProvenance = binaryNativeCode`, and start with
`platforms = [ "aarch64-darwin" ]`. Fixups or post-install mutation would break
the upstream signature.

Add read-only package checks for:

- the expected bundle ID and version;
- a main executable containing `arm64`;
- strict recursive code-signature verification;
- hardened runtime and no unexpected entitlements;
- a stapled notarization ticket and Gatekeeper acceptance on a macOS runner;
- hashes and architectures of embedded executable templates.

The package should install the application only. It must not launch it, edit its
configuration, or register generated Finder Sync extensions during activation.

### Declarative replacement package

Put the new source package at a separate name such as
`pkgs/by-name/fi/finder-favorites`. Build it from pinned source with SwiftPM and
the Xcode SDK available to the existing Darwin CI. Export the CLI first. Add the
application bundle only when it uses the same tested core.

The Nix derivation should run pure unit tests, formatter and linter checks, and
an ARM architecture assertion. Keep live Finder integration tests as explicit
Darwin CI jobs on disposable users or virtual machines. Export a package smoke
test that runs `--version`, `--help`, schema validation, and the in-memory
backend. Do not make a user's sidebar part of an ordinary flake check.

## Delivery roadmap

### Phase 0: correct the baseline

Keep the current module disabled on Apple silicon. Report the Nixpkgs mismatch
or patch its metadata so the old binary is not advertised as
`aarch64-darwin`. Do not merely add Rosetta as a dependency.

Package SidebarFavorites for optional interactive use if custom icons and its
GUI are valuable now. This phase does not change Home Manager favorites.

### Phase 1: prove the narrow backend

Build the Objective-C bridge and a Swift `doctor` executable. Test read,
insert, move, property-free update, and remove on a disposable macOS 26.1 and
current 26.x account. Measure item IDs, seeds, duplicate behavior, stale rows,
and refresh timing. Stop if writes need Full Disk Access or broad TCC grants.

The exit criterion is a published compatibility matrix and automatic restoration
of the disposable account after every failure injection.

### Phase 2: ship a safe CLI

Implement the pure planner, versioned JSON, dry-run, additive apply, ownership
state, journal, verification, export, import, and stable exit codes. Package the
CLI in `nixpkgs-personal`. Run at least one macOS point-release cycle with manual
invocation before connecting it to activation.

### Phase 3: reconnect Home Manager

Replace the `mysides` package option with the new package and versioned config.
Offer `manual` and `initialize` first. Add `reconcile` only after drift,
concurrency, and rollback tests pass. Preserve unrelated favorites by default.

### Phase 4: add the native app

Build the SwiftUI interface over the same planner. Add drag ordering, plan
preview, undo, import and export, diagnostics, manual fallback, keyboard
control, and VoiceOver. Keep custom icons and background operation out of this
phase.

### Phase 5: harden distribution and maintenance

Add Developer ID release automation, notarization, stapling, CodeQL, sanitizers,
fuzzing, reproducible Nix source builds, and macOS beta smoke tests. Document an
OS support window and remove write support immediately when the backend fails a
new release. Read-only diagnosis and the manual Finder fallback must continue to
work when automatic writes are disabled.

## Final call

The current configuration did not misdiagnose the installed artifact. Nixpkgs
did. Rebuilding the decade-old source for ARM would fix only the executable
slice, while adopting a private `.sfl4` editor would trade that simple problem
for data-loss and privacy risks.

Package SidebarFavorites if an interactive, polished manager is useful today.
For declarative Nix control, build the smaller Swift tool described here. Its
quality will come from modest scope, explicit ownership, verified minimal
changes, and an honest unsupported-backend switch. If Apple removes
`LSSharedFileList`, fall back to one manually added Finder favorite that points
at a Nix-managed directory of symlinks. That fallback is less direct, but it is
supported, reversible, and cannot corrupt Finder's state.

## Implemented decision

The repository now follows the Swift CLI recommendation. The source package is
`pkgs/pkgs/by-name/fi/finder-favorites`, and the Home Manager interface is
`modules/home/macos/finder-favorites.nix`. The M4 profile enables additive
reconciliation with the required deprecated-backend acknowledgement.

The shipped implementation includes a narrow C bridge, a pure Swift planner,
versioned JSON, list and export commands, plan and drift checks, dry-run apply,
per-user locking, a private transaction journal, rollback, crash recovery,
fresh-snapshot verification, strict configuration limits, root rejection,
warning-free compilation, SwiftLint and swift-format policy, XCTest coverage,
and a release-built in-memory self-test for the Nix derivation. A read-only
smoke test on macOS 26.6.2 successfully resolved the live sidebar on Apple
silicon. No live write was performed during development or verification.
