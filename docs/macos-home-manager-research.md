# macOS Home Manager module research

## Scope and baseline

This report reviews `modules/home/macos` and the active MacBook settings that
consume it. The machine is an M4 MacBook Pro running macOS 26.6.2 on `arm64`.
The flake pins Home Manager at
[`99c9ec63`](https://github.com/nix-community/home-manager/tree/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11),
nix-darwin at
[`4cff07de`](https://github.com/nix-darwin/nix-darwin/tree/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48),
and Nixpkgs at
[`9fbb54b3`](https://github.com/NixOS/nixpkgs/tree/9fbb54b33e91ee4ca368e35a78e0613c720600b3).
The Mac uses Home Manager inside nix-darwin, not standalone Home Manager.

The review is based on those pinned sources, current Apple documentation, and
read-only inspection of the active host. No module source was changed.

## Decision

Keep Home Manager responsible for user packages, app copies, the Dock helper,
and optional user preferences. Move machine policy, especially Software Update,
to nix-darwin. Do not try to declare TCC grants on this unmanaged Mac.

The current setup has several sound ideas. App bundles have stable copied paths,
Dock targets are validated before destructive changes, Dock restarts are batched,
screenshots use private temporary files, and most common Finder, keyboard, and
trackpad values match typed upstream options. The weak spots are ownership and
version drift. A few settings target the wrong domain, several old private keys
have outlived the macOS feature they controlled, and two third-party helpers sit
outside their upstream compatibility guarantees.

Fix these in order:

1. Remove `preferences/software-update.nix` from Home Manager and express the
   supported update policy at the nix-darwin system layer.
2. Change `AppleKeyboardUIMode` from `3` to `2` on this macOS 26 host.
3. Disable the current Finder favorites activation on Apple silicon until the
   Intel-only `mysides` dependency is removed. At minimum, make it opt-in,
   dry-run safe, and visibly best-effort.
4. Make Dock reconciliation inspect actual Dock state instead of trusting only
   a desired-state hash. Order it after `setDarwinDefaults` and restart Dock when
   Dock preferences change.
5. Trim Safari, Finder, Mail, iTunes, and animation settings to current,
   UI-backed or upstream-typed keys. Put private knobs behind an explicit
   `experimental` option.
6. Replace runtime `xcrun swift` OCR with a compiled, signed helper that checks
   Screen Recording access and gives the user an actionable onboarding path.
7. Split the GNU userland into an opt-in compatibility profile. Stop silently
   pretending Linux-only packages exist on Darwin.

## What Home Manager actually does

`targets.darwin.defaults` is a user-defaults interface. Home Manager serializes
each configured domain to a plist, filters out `null` values, and runs
`/usr/bin/defaults import` after `writeBoundary`. `currentHostDefaults` runs the
same operation with `-currentHost`.
[Pinned Home Manager implementation](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/targets/darwin/user-defaults/default.nix#L11-L34)

This has four consequences for this repository:

- Nix values become real plist types. `true`, `1`, `"1"`, `[ ]`, and `"()"`
  are different values. Apple defines property lists as typed arrays,
  dictionaries, strings, data, dates, and numbers.
  [Apple property-list documentation](https://developer.apple.com/library/archive/documentation/General/Conceptual/DevPedia-CocoaCore/PropertyList.html)
- `null` means "do not write." It does not delete or restore a setting. Removing
  an attribute from Nix also leaves the last value in the preferences database.
  Home Manager documents this directly and nix-darwin gives the same manual
  deletion warning for settings whose default is represented by absence.
  [Home Manager option implementation](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/targets/darwin/user-defaults/default.nix#L39-L81),
  [nix-darwin example](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults/NSGlobalDomain.nix#L42-L65)
- Home Manager does not restart Finder, Safari, Mail, or every process that
  caches defaults. Apple warns that changing a running application's defaults
  may be missed or overwritten by the application. Home Manager only says some
  settings need a new login.
  [Home Manager warning](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/targets/darwin/user-defaults/default.nix#L48-L59),
  [Apple `defaults` guidance](https://support.apple.com/en-lamr/guide/terminal/-apda49a1bb2-577e-4721-8f25-ffc0836f6997/mac)
- Two modules writing the same domain can race or undo each other's assumptions.
  Pick one owner for Dock items, Finder settings, browser handlers, and each
  system policy.

The activation boundary is used correctly in the Dock and defaults modules.
Home Manager's activation DAG distinguishes checks before `writeBoundary` from
mutations after it. Custom commands should use Home Manager's `run` helper so
`home-manager switch --dry-run` prints them without executing them.
[Home Manager activation design](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/docs/manual/internals/activation.md)

## Validated findings

| Priority | Current file | Finding | Required change |
| --- | --- | --- | --- |
| Critical | `preferences/software-update.nix` | It writes the per-user `com.apple.SoftwareUpdate` domain. nix-darwin writes update policy to `/Library/Preferences/com.apple.SoftwareUpdate` as root. The current values therefore do not own the machine policy they claim to own. | Move supported update settings to `modules/darwin`. Delete legacy `ScheduleFrequency`. Verify the macOS 26 Background Security Improvements switch separately. |
| High | `finder-favorites.nix` and `finder_favorites.py` | `mysides` 1.0.1 is an unsigned, Intel-only executable on this ARM Mac and uses deprecated `LSSharedFileList`. It currently works only because Rosetta is installed. | Disable on `aarch64-darwin` now or make it manual. Do not invest in a new declarative abstraction around a deprecated API. |
| High | `finder-favorites.nix` | The activation invokes the Python helper directly, not through `run`, so a dry run can create directories and modify Finder favorites. | Wrap the command in `run`, and make the Python helper support a no-write check mode. |
| High | `preferences/accessibility.nix` | `AppleKeyboardUIMode = 3` is the old macOS value. Pinned nix-darwin says `2` enables keyboard UI control on Sonoma or later and `3` is for older releases. | Use `2` on macOS 26. Add a current-OS assertion or stop setting the raw key from Home Manager. |
| High | `dock-items.nix` | The cache hash contains desired configuration only. If the user or macOS changes the Dock later, an unchanged Nix generation skips reconciliation forever. | Compare normalized `dockutil --list` output with desired state, or always reconcile. Keep a hash only as an optimization after actual-state validation. |
| High | `ocr-capture.nix` | Every capture invokes `xcrun swift`, so the helper compiles at use time and requires Xcode Command Line Tools. It does not preflight Screen Recording access. | Build one native executable, sign it consistently, preflight permission, and show the exact System Settings path when permission is missing. |
| Medium | `preferences/safari.nix` | `IncludeInternalDebugMenu`, `DebugSnapshotsUpdatePolicy`, and several old search/bookmark keys are private and untyped. On the active macOS 26 host, the configured keys were absent from Safari's current container preferences. `ProxiesInBookmarksBar = "()"` is a plist string, not an empty array. | Keep `AutoOpenSafeDownloads = false` and supported developer-menu behavior. Remove the internal debug settings and unverified keys, or gate them as experimental per macOS version. |
| Medium | `preferences/applications.nix` | The iTunes domain is obsolete on a Tahoe machine. `com.apple.terminal` is not the canonical domain spelling used by Home Manager. The Mail setting was absent from the current sandboxed Mail preferences. | Remove iTunes configuration. Spell the Terminal domain `com.apple.Terminal`, or use `programs.macos-terminal`. Treat the Mail key as unverified. |
| Medium | `preferences/input.nix` | Two-finger right click is enabled while the Bluetooth trackpad also requests bottom-right-corner secondary click. Those are competing UX choices in the typed nix-darwin model. | Pick one secondary-click mode. For the current intent, keep `TrackpadRightClick = true` and remove `TrackpadCornerSecondaryClick = 2`. |
| Medium | `core-packages.nix` and `default-packages.nix` | Linux-only names are silently filtered out. The `pkgs.stdenv.cc.libc` result on this host is an empty `libSystem-B` output. GNU commands broadly shadow macOS commands, which changes CLI behavior beyond the few native wrappers. | Use an explicit Darwin package list, warn for requested unavailable tools, remove the empty libc output, and make GNU shadowing an opt-in profile. |
| Medium | `dock-items.nix` | Pinned `dockutil` is 3.1.3. Its upstream compatibility statement ends at Sonoma, while the host runs Tahoe 26. | Add a runtime smoke test and a supported-version note. Fail with an actionable message instead of partly rebuilding the Dock. |
| Low | `preferences/animations.nix` and `preferences/finder.nix` | Several private timing, SpringBoard, Quick Look, and sidebar disclosure keys have no current typed upstream option. Tahoe exposes apps through Spotlight rather than the old Launchpad workflow. | Prefer Reduce Motion and Reduce Transparency. Move private values to a clearly named experimental profile and test them after each macOS upgrade. |

## System preferences belong in nix-darwin

The Software Update block is the clearest ownership error. Pinned nix-darwin's
writer treats Software Update as a system domain at
`/Library/Preferences/com.apple.SoftwareUpdate`; it runs Dock, Finder, global,
trackpad, and other user settings as `system.primaryUser`.
[nix-darwin defaults writer](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults-write.nix#L22-L48)

The typed nix-darwin option currently covers
`system.defaults.SoftwareUpdate.AutomaticallyInstallMacOSUpdates`.
[Pinned option](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults/SoftwareUpdate.nix)
Use that rather than a Home Manager user domain. Do not copy every old blog-post
key into `CustomSystemPreferences`. Apple now separates ordinary macOS updates,
system data and security updates, and Background Security Improvements. Apple
calls prompt background installation a core security control and documents a
separate Background Security Improvements switch on Tahoe.
[Apple background-update guidance](https://support.apple.com/en-us/101591)

For this personal, unmanaged Mac, the practical target is:

- enable the typed nix-darwin automatic macOS update option;
- verify "Download new updates when available" and "Install system data files
  and security updates" in System Settings after activation;
- verify "Automatically Install" under Privacy & Security, Background Security
  Improvements on macOS 26;
- avoid a scheduled activation that automatically runs `softwareupdate
  --install --all --restart`, because it can terminate work and reboot the Mac.

Apple's fully declarative Software Update settings are device-management
declarations for supervised devices. They are not a Home Manager interface for
an unmanaged laptop.
[Apple `SoftwareUpdateSettings`](https://developer.apple.com/documentation/devicemanagement/softwareupdatesettings)

The same ownership rule applies when a typed nix-darwin option exists. Finder,
Dock, trackpad, NSGlobalDomain, screensaver, screencapture, and accessibility
all have typed system options. Typed options catch invalid enums and document
OS-sensitive values. Freeform Home Manager defaults remain useful for genuine
per-user preferences that nix-darwin does not expose, but they should be the
exception.

## Accessibility and animation behavior

`AppleKeyboardUIMode = 3` is wrong for the current OS. Pinned nix-darwin defines
`0` as disabled, `2` as enabled on Sonoma or later, and `3` as enabled only on
older macOS.
[Pinned option semantics](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults/NSGlobalDomain.nix#L76-L85)

The animation module tries to improve responsiveness by forcing private timing
values near zero. That can work, but it is not the same as accessible reduced
motion. Apple provides a supported Reduce Motion setting, and nix-darwin exposes
it as `system.defaults.universalaccess.reduceMotion`; Reduce Transparency is
available beside it.
[Apple motion guidance](https://support.apple.com/guide/mac-help/customize-onscreen-motion-mchlc03f57a1/mac),
[nix-darwin universal-access options](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults/universalaccess.nix)

A better interface has three user-selectable modes:

- `normal`, leaving Apple timing defaults alone;
- `reduced`, enabling the supported Reduce Motion preference;
- `instant`, adding the private duration keys with an explicit compatibility
  warning.

`AppleFontSmoothing = 2` is accepted by the pinned nix-darwin type, but current
Apple UI documentation does not promise that it changes Retina rendering. Keep
it only if an A/B test on this display shows a useful difference. Do not label
it as a general accessibility improvement.

## Finder and sidebar management

Most of `preferences/finder.nix` maps to current Finder controls or typed
nix-darwin options: list view, current-folder search, 30-day Trash cleanup,
extensions, path and status bars, hidden files, desktop icons, extension-change
warnings, and folders-first sorting.
[Pinned nix-darwin Finder options](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults/finder.nix),
[current Apple Finder settings](https://support.apple.com/guide/mac-help/change-finder-settings-on-mac-mchlp2803/mac)

Several values are preferences, not universal improvements. Showing hidden files
can make Finder noisy and increases the chance of accidental edits. Hiding all
desktop icons is clean but removes a familiar drop target. Quitting Finder can
leave users without the normal file browser until it relaunches. Expose these as
host or profile choices instead of branding them as performance settings.

Treat `QLEnableTextSelection`, `SidebarDevicesSectionDisclosedState`,
`SidebarPlacesSectionDisclosedState`, and `OpenWindowForNewRemovableDisk` as
compatibility-tested private settings. None has a current typed option in the
pinned nix-darwin Finder module. `DisableAllAnimations` belongs with the
experimental animation profile.

The favorites helper has deeper problems:

- It computes labels with `baseNameOf`, so two paths with the same final name
  collide.
- It deduplicates paths, not labels.
- A failed `mysides list` is treated like an empty sidebar.
- It updates or adds configured items but never removes an item dropped from
  Nix and never enforces order.
- It creates every directory itself even though this host already sets
  `xdg.userDirs.createDirectories = true`.
- It bypasses Home Manager's `run` wrapper, so dry-run is not safe.

Apple supports manual Finder sidebar aliases and reorder-by-drag. It does not
publish a current declarative command-line API for the same operation.
[Apple Finder sidebar documentation](https://support.apple.com/guide/mac-help/customize-the-finder-sidebar-on-mac-mchl83c9e8b8/mac)
`mysides` says it is built around `LSSharedFileList`; Apple lists those APIs as
deprecated.
[`mysides` 1.0.1 source](https://github.com/mosen/mysides/tree/v1.0.1),
[Apple Launch Services deprecated symbols](https://developer.apple.com/documentation/coreservices/launch_services/deprecated_symbols)

The architecture problem makes this urgent. Nixpkgs downloads the upstream
1.0.1 package rather than compiling an ARM program.
[Pinned Nixpkgs package](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/pkgs/by-name/my/mysides/package.nix)
Local inspection reports `Mach-O 64-bit executable x86_64` and no code signature.
Apple announced that macOS 27 is the final general Rosetta release and that
Intel-only non-game binaries will stop working on Apple silicon after it.
[Apple Rosetta transition notice](https://developer.apple.com/news/?id=w5ngl9k2),
[Apple support guidance](https://support.apple.com/en-gb/102527)

For this Mac, manual sidebar setup is safer than preserving this dependency.
If the helper remains temporarily, add an `enable` option defaulting to false,
assert `!pkgs.stdenv.hostPlatform.isAarch64`, use `run`, fail if listing fails,
reject duplicate labels, and document that it is additive rather than
declarative.

## Dock management

The custom Dock module gets several things right. It accepts tagged apps,
spacers, and folders; validates every target before `--remove all`; waits for
copied or linked app activation; and uses `--no-restart` on every operation
except the last. `dockutil` documents all of those operations.
[`dockutil` 3.1.3](https://github.com/kcrawford/dockutil/tree/3.1.3)

Keep those properties, but replace the current cache rule. The SHA-256 hash only
contains the desired item list, package path, and apps directory. It says nothing
about the current Dock. A manual reorder, a removed app, or an OS-added item does
not change the hash, so the next activation prints "unchanged" and preserves the
drift.

Two reasonable modes should be explicit:

- `authoritative`: normalized actual state must equal desired state; otherwise
  rebuild the Dock;
- `initialize`: apply once, then let the user edit freely.

The current behavior accidentally mixes the two. Its option name and remove-all
implementation imply authoritative management, while its hash behaves like
initialization.

Add a dependency on `setDarwinDefaults`. A Dock preference change currently has
no guaranteed relationship to `syncDockItems`, and a cache hit means dockutil
does not restart Dock. Pinned nix-darwin restarts Dock whenever it writes Dock
preferences, which is the behavior to preserve if the custom module remains.
[nix-darwin restart logic](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults-write.nix#L153-L157)

Do not enable nix-darwin `persistent-apps` and this module together. nix-darwin
already has typed persistent app and folder options, but the custom module has a
useful Home Manager app-name resolver and better preflight. Choose one owner.
[nix-darwin Dock item options](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults/dock.nix#L130-L246)

Finally, pinned dockutil 3.1.3 only claims compatibility through Sonoma in its
README. Tahoe 26 is outside that statement. A `dockutil --list` smoke test on
activation should fail before remove-all if the output cannot be parsed.

## App copies and Launch Services

The host explicitly enables `targets.darwin.copyApps` and disables `linkApps`.
That is the correct choice for stable app paths, Spotlight discovery, and tools
that need real writable bundles. Home Manager itself now defaults to copied apps
for state versions 25.11 and newer and describes the copy mode as the one that
works with Spotlight.
[Pinned copy-app implementation](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/targets/darwin/copyapps.nix#L10-L29)

This repository keeps `home.stateVersion = "25.05"`, so the explicit
compatibility override is necessary. Home Manager otherwise defaults old state
versions to linked apps.
[Pinned link-app default](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/targets/darwin/linkapps.nix#L9-L23)

Copying is not cheap. Home Manager uses recursive rsync with checksums because
Nix store mtimes cannot distinguish changes, and its source calls out the speed
penalty. This is a reasonable activation cost for correct app discovery, not a
bug to work around with an ad hoc `cp`.
[Copy flags and rationale](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/targets/darwin/copyapps.nix#L102-L144)

Launch Services normally discovers apps when Finder sees them, at login, and in
Applications folders. Apple says explicit registration is rarely necessary.
[Apple Launch Services registration guidance](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/LaunchServicesConcepts/LSCTasks/LSCTasks.html)
Default handlers are different. They should use the current AppKit API and honor
its completion error and consent UI, not edit Launch Services plists.
[Apple `NSWorkspace.setDefaultApplication`](https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication%28at%3Atoopenurlswithscheme%3Acompletion%3A%29)

The macOS home folder reviewed here does not own default-browser handlers, but
its copied app directory is the correct stable input to those modules. Keep
registration, default handlers, and Dock placement as separate operations.

## TCC, privacy, and OCR

Home Manager cannot silently grant Accessibility, Screen Recording, Automation,
Full Disk Access, or App Management on an unmanaged personal Mac. Apple requires
the user to grant these permissions in Privacy & Security. Its managed Privacy
Preferences Policy Control payload requires device management and supervised,
user-approved enrollment.
[Apple privacy settings](https://support.apple.com/en-gb/guide/mac-help/mchl211c911f/mac),
[Apple PPPC deployment requirements](https://support.apple.com/en-gb/guide/deployment/dep38df53c2a/web)

Do not add `sqlite3` writes to the TCC database and do not grant Full Disk Access
to a broad shell merely to suppress onboarding. Home Manager's own app-copy
module checks App Management, can reset the relevant TCC service to trigger a
new prompt, and then stops with instructions. It never pretends to grant access.
[Home Manager App Management check](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/targets/darwin/copyapps.nix#L41-L96)

The OCR flow uses good primitives. It calls the system screenshot tool with an
argument array, stores the capture in a mode-restricted temporary file, removes
the file in `finally`, uses Apple's on-device Vision request, and sends text to
`pbcopy` without a shell. The remaining work is UX and stable identity:

- call `CGPreflightScreenCaptureAccess` before showing the capture UI;
- call the request API only as part of an explicit onboarding action;
- tell the user to enable Screen & System Audio Recording and restart the app;
- compile the Swift helper once instead of running `xcrun swift` for every shot;
- give the executable a stable signed identity so permission survives Nix store
  path changes as reliably as macOS allows;
- explain that recognized text stays in the system clipboard until replaced and
  can be read by software with pasteboard access.

Apple exposes preflight and request APIs for this purpose and documents the user
grant in System Settings.
[Apple screen-capture preflight](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess%28%29),
[Apple screen-capture request](https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess%28%29),
[Apple Screen Recording settings](https://support.apple.com/en-ie/guide/mac-help/mchld6aa7d23/mac)

Notifications may also prompt on first use. Treat that prompt as onboarding,
not a failure that activation should work around.

## Safari and application preferences

Keep `AutoOpenSafeDownloads = false`. Safari still exposes "Open safe files
after downloading," and leaving it off avoids automatically opening documents
that happen to match Safari's safe-file list.
[Apple Safari General settings](https://support.apple.com/en-gb/guide/safari/ibrw1072/mac)

Keep developer features only if this is a development workstation. Home Manager
already maps `IncludeDevelopMenu` into the additional WebKit and SandboxBroker
domains that current Safari needs. Apple documents the supported "Show features
for web developers" control.
[Home Manager Safari mapping](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/targets/darwin/user-defaults/opts-allhosts.nix),
[Apple Safari Advanced settings](https://support.apple.com/guide/safari/advanced-ibrw1075/mac)

Remove `IncludeInternalDebugMenu` and `DebugSnapshotsUpdatePolicy` from the
default profile. Internal debug behavior is not a normal user feature or a
security control. It changes without compatibility guarantees.

The intent behind disabling search suggestions is defensible. Apple confirms
that disabling search-engine suggestions prevents partial queries from being
sent as the user types. The current Safari UI has separate controls for search
engine suggestions and Safari Suggestions.
[Apple Safari search privacy](https://support.apple.com/en-nz/guide/safari/ibrwe75c2a3c/26.0/mac/26)
Apple does not publish current plist keys for those controls. The repository's
old `UniversalSearchEnabled` and `SuppressSearchSuggestions` values were absent
from the active Safari container on this host. Prefer a documented one-time UI
step over claiming those old keys are enforced.

`ProxiesInBookmarksBar = "()"` should not survive review. It is unambiguously a
string in the generated plist. If the intention is an empty plist array, Nix
syntax is `[ ]`. More importantly, the setting is not in current Safari UI or a
typed Home Manager option, so removal is safer than changing its type blindly.

Remove the iTunes preference. Tahoe uses Music and the configured domain is
dead configuration. Canonicalize `com.apple.terminal` to `com.apple.Terminal`.
Pinned Home Manager uses the capitalized bundle identifier in its Terminal
module and can import generated Terminal profiles itself.
[Home Manager Terminal module](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/programs/macos-terminal.nix#L109-L176)
Keep the Mail pasteboard setting only after verifying that it appears in Mail's
sandboxed preference domain and changes current Mail behavior. It was absent on
the inspected host.

## Packages and Apple silicon

`pkgs` is evaluated for `aarch64-darwin`, so ordinary Nix-built CLI packages are
native to Apple silicon. `lib.meta.availableOn` checks declared platform
metadata. It does not inspect a downloaded Mach-O binary, which is why `mysides`
passes the filter despite containing only `x86_64` code.
[Nixpkgs platform metadata](https://nixos.org/manual/nixpkgs/unstable/#sec-meta-platforms)

The current package lists silently omit at least the Linux-oriented `acl`,
`attr`, `libcap`, `strace`, and `su` entries on Darwin. Silent omission is fine
for an optional convenience set, but not for a module called `core-packages`.
Use an explicit Darwin list and document replacements. `strace` in particular
does not become available by listing it; macOS diagnostics use tools such as
Instruments, `sample`, `spindump`, and restricted DTrace facilities.

Remove `pkgs.stdenv.cc.libc` from `home.packages`. On the evaluated host it is
`libSystem-B` with empty `include` and `lib` directories and adds no command.

GNU command shadowing should be a visible choice. The native wrappers for
`stty`, `nc`, `ps`, `top`, and `tar` recognize real Darwin incompatibilities,
but broad shadowing still changes `date`, `stat`, `readlink`, `sed`, and other
commands that scripts may expect to be BSD variants. Offer:

- a conservative native-first profile;
- a GNU-first profile with prefixed escape hatches such as `gtar`;
- an assertion or warning when a requested core tool is unavailable.

The current Bash wrapper adds a shell process before each final `exec`. Direct
symlinks to fixed absolute system commands avoid that startup cost and are
sufficient for these aliases.

## Proposed module shape

A feature-rich interface should expose policy without forcing every preference
on every Darwin user:

```nix
macos = {
  preferences = {
    enable = true;
    owner = "nix-darwin";
    motion = "reduced"; # normal, reduced, instant
    finder = {
      showHiddenFiles = false;
      showAllExtensions = true;
      cleanTrashAfter30Days = true;
    };
    safari = {
      disableSafeFileAutoOpen = true;
      developerFeatures = true;
      experimentalDefaults = false;
    };
  };

  dock = {
    enable = true;
    mode = "authoritative"; # or initialize
  };

  finderFavorites = {
    enable = false;
    backend = "manual";
  };

  ocrCapture = {
    enable = true;
    showOnboarding = true;
  };

  commandProfile = "native-first"; # or gnu-first
};
```

Use `lib.mkDefault` for opinionated values so a host can override them. Keep
machine-wide security in `modules/darwin`, not behind this Home Manager API.
Add assertions for mutually exclusive preference owners and secondary-click
modes. Every private default should name the macOS versions on which the
repository tests it.

## Verification plan

Evaluation and activation tests should cover behavior, not just Nix syntax.

1. Evaluate the Mac configuration and inspect the generated activation script.
   Confirm Software Update no longer appears in Home Manager defaults.
2. Run Home Manager dry-run with Dock and Finder favorites enabled. Nothing on
   disk, in Finder, or in the Dock should change.
3. Change one Dock item manually, reactivate the same generation, and verify
   `authoritative` mode restores it while `initialize` mode leaves it alone.
4. Remove a managed preference from Nix. The activation output must say whether
   the old key remains or is explicitly deleted. Do not leave reset semantics
   implicit.
5. Run `file` and `codesign -dv` on every packaged macOS helper. Reject Intel-only
   helpers on `aarch64-darwin` unless Rosetta is an explicit temporary policy.
6. Test OCR with Screen Recording denied, granted, and revoked. Each state should
   produce one clear user action and no orphaned screenshot.
7. Check Safari and Mail settings only while the apps are closed, reopen them,
   and confirm the corresponding visible UI control. Delete keys that do not
   survive this test.
8. After each macOS major update, run a small compatibility suite for Dock,
   Finder, Safari, trackpad, screenshots, app copying, Spotlight discovery, and
   default handlers before activating private defaults.

This produces a smaller default configuration than the current one, but a more
capable module. Supported features become dependable, experimental features are
honest about their limits, and personal choices remain easy to override.
