# Duplicate macOS application results in Spotlight

Reviewed: 2026-10-14. Scope: macOS 27.0.1, live application metadata and
registrations, Home Manager pin `c58f54c733a7894d84fa2fdff26cc12088c4b78c`, and
nix-darwin pin `4cff07de74b50e64bdd68cd4e722ab5b6b35ee48`.

## Answer

There are distinct issues: Spotlight includes settings results alongside apps,
and this installation exposes some apps through competing filesystem paths.
The `.app` suffix does not distinguish these cases. Keep the copied Home Manager
bundles as the canonical applications, retire confirmed obsolete links, and
align command-line launches with those bundles. Treat settings-result visibility
as a separate preference. Do not reset the entire Spotlight or Launch Services
database as the first repair.

## Findings and sources

### Spotlight results and displayed names

Apple documents Applications browse mode (Command-1) and separate result filters
for apps and System Settings, including `kind:app` and `kind:settings`.
[Apple Spotlight filtering](https://support.apple.com/guide/mac-help/mchl4d69efd3/mac).

A result reported to open System Settings belongs to that behavior, rather than
establishing a second executable installation. Its gear badge is consistent with
that interpretation; no first-party specification for the exact badge was found.
The investigation did not inspect the Spotlight UI or identify the subpane opened.

The live metadata reports `com.apple.application-bundle` for ChatGPT, VS Code,
and Vesktop. All three have display names ending in `.app`; so does Apple's
Calculator. The live Finder preference enables showing extensions, matching
[the repository's macOS defaults](../../modules/darwin/macos.nix).
This rules out using the suffix alone as evidence of a broken Nix bundle. It
does not establish Spotlight's exact naming algorithm. Apple distinguishes
filesystem names and bundle display names in its
[bundle documentation](https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFBundles/AboutBundles/AboutBundles.html).

### Real duplicate ChatGPT paths

Read-only inspection found:

- The Dock targets `$HOME/Applications/Home Manager Apps/ChatGPT.app`, a real
  copied bundle with identifier `com.openai.codex` and bundle version `12111.0`.
- A legacy `$HOME/Applications/ChatGPT.app` symlink still targets a different,
  existing Nix-store bundle, version `7982.0`.
- AppKit returns three application URLs for `com.openai.codex`: the managed
  copy, that legacy store bundle, and another store bundle.
- The installed `chatgpt` command executes the latter store bundle directly.
- AppKit currently prefers the managed copy for a bundle-ID launch.

Thus competing ChatGPT bundles are confirmed. Which Spotlight row selects which
bundle remains untested. The suffix is not sufficient to map the rows. The
identifier above is the installed package's actual identifier; it should not be
replaced with the identifier of another ChatGPT distribution.

Apple's native API explicitly returns multiple application URLs for one bundle
identifier, ordered by suitability to launch.
[NSWorkspace application URLs](https://developer.apple.com/documentation/appkit/nsworkspace/urlsforapplications%28withbundleidentifier%3A%29).
The local `lsregister -dump` corroborated the competing paths. Some historical
records are marked launch-disabled, so counting every dump entry as a launchable
duplicate would overstate the result.

### VS Code has a different evidence profile

AppKit returns one application URL for `com.microsoft.VSCode`: the managed copy.
The Dock targets that same path. `/Applications/Visual Studio Code.app` is a
symlink to the managed copy, not another installed version.

However, the installed `code` command resolves inside the Nix-store VS Code
bundle. Its script computes the application path from its own resolved location
and invokes that bundle's executable. Microsoft's upstream
[Darwin CLI script](https://github.com/microsoft/vscode/blob/main/resources/darwin/bin/code.sh)
implements this behavior; the installed script was inspected directly.

This confirms inconsistent CLI and Dock paths. It does not prove that either
Spotlight result invokes the CLI, or that the reported second instance follows
this route. The exact VS Code Spotlight symptom still needs a result-target and
process comparison. VS Code's separate AppKit result also means the legacy
ChatGPT-link diagnosis cannot simply be applied to it.

### Existing copying policy is appropriate

The profile already enables `targets.darwin.copyApps` and disables `linkApps` in
[compatibility.nix](../../homes/macbook-pro-m4/local/compatibility.nix).
The pinned [Home Manager copying module](https://github.com/nix-community/home-manager/blob/c58f54c733a7894d84fa2fdff26cc12088c4b78c/modules/targets/darwin/copyapps.nix)
materializes external symlinks as real bundles with rsync. It does not explicitly
register every copied app with Launch Services after synchronization.
The [Dock module](../../modules/home/macos/dock-items.nix) already selects the
managed application directory.

The pinned [nix-darwin application module](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/applications.nix)
also copies system apps, but live `/Applications/Nix Apps` is empty here.
It is not the duplicate producer in this observation.
Adding a second application-copying scheme would add ownership ambiguity.
Upstream [mac-app-util](https://github.com/hraban/mac-app-util/blob/master/main.lisp)
also explains that trampoline wrappers interfere with modern nix-darwin copying.
That source was retrieved on the review date; it is not a repository dependency.

## Recommended repair

1. Retain the stable Home Manager copies and existing Dock targets. Inventory
   exact links, registered URLs, versions, and running bundle URLs before making
   changes. Preserve running sessions and application data.
2. Move the confirmed legacy ChatGPT symlink outside application discovery into
   private recovery storage. Retain its original path and target for rollback.
   Do not delete its store target or change unrelated application bundles.
3. Unregister only the confirmed superseded ChatGPT store URLs with
   `lsregister -u`, then explicitly register the chosen copied bundle with
   `lsregister -f`. The installed tool's help documents both operations. Verify
   with AppKit afterward; registration changes alone do not remove the producer.
4. Route Darwin GUI CLI launches to the canonical copied bundles. For VS Code,
   preserve its native CLI by executing the copied bundle's
   `Contents/Resources/app/bin/code`, forwarding every argument and exit status.
   Verify remote-terminal IPC behavior, reuse-window behavior, paths containing
   spaces, and missing-copy errors. A generic `open -a` replacement would lose CLI
   semantics such as `--wait`.
5. For ChatGPT, inspect its supported CLI before choosing a wrapper. Preserve
   arguments and distinguish the graphical launcher from the separate `codex`
   developer CLI. Direct execution of a copied app still needs a native test for
   process reuse; it must not be assumed equivalent to Launch Services opening.
6. If copied applications remain absent from Applications browse mode, test
   scoped registration after `copyApps`. Only promote this into a reusable
   activation helper after a before/after test establishes that it fixes that
   symptom. Registering an app does not remove legitimate settings results.
7. Optionally exclude System Settings in Spotlight's result-category settings,
   or use Applications browse mode. Apple documents
   [category selection](https://support.apple.com/guide/mac-help/mchl54d95e8a/mac).
   This changes search presentation and does not fix duplicate installations.

The `/Applications` VS Code symlink should be reviewed for ownership and any
external tool that requires it before retirement. It is not evidence of another
version and should not be removed merely because it exists.

## Implemented repair

The [application module](../../modules/home/macos/applications.nix) now runs
scoped registration reconciliation after `copyApps` and before launch agents
start. Its [native helper](../../modules/home/macos/application_registry.py)
validates the copied inventory first, archives confirmed obsolete store links
with recovery journals, unregisters competing store bundles, and refreshes the
copied bundles. It preserves unrelated manually installed applications. Check
and preview modes do not modify state.

AppKit sometimes continues returning an unregistered store URL even after
Launch Services marks it `launch-disabled`. Native repeat testing exposed this
behavior. The helper excludes a store candidate only when the native registry
explicitly reports that flag; unknown dump formats retain candidates for
verification rather than silently ignoring them.

The installed `chatgpt` wrapper uses `open -a` with the copied bundle's explicit
path. The separate `codex` developer CLI is unchanged. The installed `code`
wrapper executes the copied bundle's original CLI, preserving arguments, stdin,
environment, and exit status. The [AeroSpace feature](../../modules/home/wm/aerospace.nix)
also starts its copied application, while retaining the package's IPC CLI.

Native post-activation verification exposed a case-insensitive-store collision:
upstream exported `ChatGPT` while the wrapper exported `chatgpt`. Home Manager's
environment retained the original command despite the wrapper's higher priority.
The wrapper now matches the selected package's exact `meta.mainProgram` spelling.
A lowercase alias is added only when the filesystem treats it as distinct.
This keeps command access on case-sensitive stores and makes environment
priority resolution work on the observed Mac filesystem.

A native restart experiment initially failed with launchd error 5 because
`bootout` returned before the old process exited. Waiting for the native process
exit event before bootstrap made the copied application start successfully.
The pinned Home Manager launchd implementation already uses `bootout --wait`
on macOS 26 and later; no launchd timing workaround was added to the repository.

The complete system build also exposed an independent ChatGPT packaging issue:
executing the signed GUI app for `--version` caused output finalization to fail
with an operation-not-permitted error. The package's
[version probe](../../pkgs/pkgs/by-name/ch/chatgpt-latest/bundle_version.py)
now reads `CFBundleShortVersionString` using packaged Python. This retains the
version check without executing or modifying the bundle. An initial native
`plutil` probe was denied by the build sandbox and was replaced. The corrected
native package and complete system build both passed.

## Validation and limits

The initial investigation used SSH for read-only inspection of macOS version, bundle
plists, Spotlight metadata, Dock targets, symlink destinations, CLI scripts,
Launch Services records, and AppKit application URLs. Spotlight indexing is
enabled. No matching main ChatGPT, VS Code, or Vesktop application was running
in that initial AppKit snapshot, so there was no live pair of instances to compare.

The implementation subsequently established these results:

- The native registration check failed before repair and passed afterward for
  all 30 managed apps. Repeated reconciliation and check runs passed. The old
  ChatGPT symlink is preserved in private recovery storage.
- ChatGPT CLI and Dock-equivalent opens reused the same persistent main process
  at the copied bundle path. VS Code reused its main process at its copied path.
  Its short-lived Electron CLI process can appear in an immediate AppKit
  snapshot; this does not establish a second persistent GUI instance.
- VS Code `--version`, `--reuse-window`, and `--status` worked. A native kqueue
  test confirmed `--wait` remained attached while a temporary document was open
  and returned zero after the investigation-started editor closed normally.
- AeroSpace's copied application started and answered the existing IPC CLI.
  Strict signature verification reported the same pre-existing resource-signature
  failure for both its store and copied bundles; no signatures were changed.
- Twenty focused Python behavior tests passed on Linux, covering recovery,
  scoped cleanup, disabled registry records, dry-run behavior, argument forwarding,
  missing-copy errors, case-aware aliases, and existing macOS helpers. Python, JavaScript, and type
  checks passed for the new helper sources.
- The package repository's `just check` passed evaluation across all three
  exported systems. The corrected ChatGPT package, application command package,
  complete Darwin system, and deployment wrapper built natively on the Mac.
- Full system activation succeeded, including copied-app reconciliation and Dock
  synchronization. The temporary investigation launcher package was then removed
  from the user profile; commands resolve through the managed system profile.
  After activation and the ChatGPT package upgrade, repeated CLI and
  bundle-identifier opens retained one persistent main process per tested app
  at the copied path. All 30 registration checks passed again, and AeroSpace IPC
  remained available.

Spotlight's visual rows could not be automated because the remote session lacks
Accessibility permission. There is no direct capture mapping each originally
reported row to its target. The native tests cover the underlying application
selection and launch paths; they do not prove the exact visual menu contents.
Remote-terminal IPC routing remains in the original VS Code CLI, but an actual
remote-terminal session was not exercised. Settings-result preferences and
extension visibility were preserved. No global index or registration database
reset was performed.

Acceptance for an implemented repair: launching each app through the Dock,
Spotlight Applications mode, and its CLI uses the intended bundle and reuses the
expected running application. Settings results retain their documented behavior
unless explicitly hidden. Repeat after a Home Manager activation and one app
upgrade to detect registration or path drift. Check CLI exit status and `--wait`
separately. Visual Spotlight selection remains a manual acceptance check.
