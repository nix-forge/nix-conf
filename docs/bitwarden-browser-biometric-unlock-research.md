# Bitwarden browser biometric unlock on NixOS and macOS

Research date: 2026-09-02

## Recommendation

Use the Bitwarden desktop application as the browser biometric broker. Firefox, Zen, and Chromium extensions should talk to its `com.8bit.bitwarden` native-messaging host. On Linux, Bitwarden authenticates through its narrow Polkit action backed by `pam_fprintd`. This workstation also enables NixOS's standard fprintd integration across PAM so the same enrolled fingerprint can unlock login, sudo, Polkit, greetd, and screen lockers with password fallback. On macOS, keep both Bitwarden and Zen in their upstream-signed application bundles so Touch ID, Keychain access, and native messaging retain their expected code identities.

The configuration can be shared without putting module configuration in `lib/` or passing values through `_module.args`:

- Put the shared native-host derivations and browser wiring in `modules/home/browsers/shared/bitwarden-native-messaging.nix`.
- Import that module normally from the browser aggregate module. Define package values in a lexical `let` or ordinary module options.
- Keep device-specific fingerprint enablement, enrollment notes, and host overrides under `hosts/*/local/` or `homes/*/local/`.
- Keep the signed macOS Bitwarden package in `nixpkgs-personal`; the Home Manager module should only select and integrate the package.

This division follows the actual trust boundaries. Native-messaging manifests are portable browser configuration. Fingerprint hardware and PAM exposure are host policy. macOS application copying and launch behavior are platform integration.

## Current repository implications

The worktree already has most prerequisites in the right layers:

- Firefox and Zen force-install Bitwarden's official extension.
- The Linux desktop has GNOME Keyring and an active graphical Polkit agent.
- The host-local Linux module installs Bitwarden's upstream Polkit action and enables NixOS's maintained fprintd integration across PAM services.
- The Home Manager Bitwarden module installs the selected desktop bridge and provides platform login integration.
- On macOS, the existing `nixpkgs-personal` overlay supplies Bitwarden's official DMG package. Home Manager copies the signed application to a stable path; Zen uses signed package mode.
- The shared browser module installs one exact-ID Gecko manifest for Firefox and Zen and one exact-origin Chromium manifest for Chrome, Chromium, and Helium. The files remain user-writable so Bitwarden can complete its explicit approval handshake; Home Manager restores their narrow allowlists and current proxy path on every activation.
- The Chrome system policy force-installs the official stable Bitwarden extension. Helium already receives that extension through the shared Chromium policy.

The implemented manifest `path` is selected per platform: the Nixpkgs `libexec/desktop_proxy` on Linux and the proxy inside the final copied Bitwarden application on macOS. The JSON definitions live once in the shared browser module rather than being duplicated in each browser adapter.

The reusable Bitwarden module exposes login startup as an option; the personal choice to enable it for both homes is kept in `homes/shared/local/browsers/bitwarden.nix`.

## Support status

| Platform | Browser | Status | Recommended path |
| --- | --- | --- | --- |
| NixOS | Firefox release | Supported by Bitwarden | Nixpkgs desktop app, Mozilla native-host manifest, Polkit, and `pam_fprintd` |
| NixOS | Zen | Compatibility path, not named in Bitwarden's support table | Use the Firefox extension ID and Mozilla native-host directory; retest after Zen updates |
| NixOS | Chromium and Chrome-store derivatives | Supported browser family | Install a Chromium manifest in each browser's actual config directory |
| macOS | Firefox release | Supported by Bitwarden | Official signed Bitwarden app plus Mozilla native-host manifest |
| macOS | Zen | Compatibility path, not named in Bitwarden's support table | Keep Zen upstream signed and install the manifest in Mozilla's directory; optionally mirror Bitwarden's Zen path |
| macOS | Chromium and Chrome-store derivatives | Supported browser family | Official signed Bitwarden app plus a per-browser Chromium manifest |

Bitwarden currently documents Chromium-based browsers, Firefox 87 and newer, and Safari 14 and newer. It explicitly says Firefox ESR is unsupported. Its desktop feature table marks browser-extension biometrics as available for the macOS DMG and App Store builds and for Linux AppImage, Snap, Flatpak, `.deb`, and `.rpm` builds. Nixpkgs is not one of Bitwarden's published binary formats, but its package builds the first-party desktop source and the same native proxy. [Bitwarden biometric unlock documentation](https://bitwarden.com/help/biometrics/) and [desktop feature support](https://bitwarden.com/help/desktop-app-feature-support/) are the controlling support statements.

Zen is Firefox-derived, but Bitwarden does not list it as a supported browser. Bitwarden's current desktop source knows a macOS Zen manifest location but has no corresponding Linux Zen entry. Zen's own Linux issue tracker records that native hosts are found in Mozilla's directory rather than `~/.zen/native-messaging-hosts`. Treat Zen unlock as tested compatibility, not a vendor guarantee. [Bitwarden native-messaging source](https://github.com/bitwarden/clients/blob/main/apps/desktop/src/main/native-messaging.main.ts) and [Zen Linux issue #10622](https://github.com/zen-browser/desktop/issues/10622) support that distinction.

## Native-messaging contract

The host name is exactly `com.8bit.bitwarden`, and the file must be named `com.8bit.bitwarden.json`. Both browser families require an absolute executable path on Linux and macOS.

### Gecko manifest

```json
{
  "name": "com.8bit.bitwarden",
  "description": "Bitwarden desktop <-> browser bridge",
  "path": "/absolute/path/to/desktop_proxy",
  "type": "stdio",
  "allowed_extensions": [
    "{446900e4-71c2-419f-a6a7-df9c091e268b}"
  ]
}
```

The GUID is Bitwarden's Firefox extension ID. Mozilla requires `allowed_extensions` to contain exact extension IDs. [Mozilla's native manifest reference](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_manifests) and [Bitwarden's generated manifest](https://github.com/bitwarden/clients/blob/main/apps/desktop/src/main/native-messaging.main.ts) agree on the schema and ID.

### Chromium manifest

The smallest production allowlist for the stable Chrome Web Store extension is:

```json
{
  "name": "com.8bit.bitwarden",
  "description": "Bitwarden desktop <-> browser bridge",
  "path": "/absolute/path/to/desktop_proxy",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://nngceckbapebfimnlniiiahkandclblb/"
  ]
}
```

Bitwarden's upstream production set also contains these exact origins:

```text
chrome-extension://nngceckbapebfimnlniiiahkandclblb/  Chrome stable
chrome-extension://hccnnhgbibccigepcmlgppchkpfdophk/  Chrome beta
chrome-extension://jbkfoedolllekgbhcbcoahefnbanhhlh/  Microsoft Edge
chrome-extension://ccnckbpmaceehanjmeomladnmlffdjgn/  Opera
```

Only include origins for extension builds actually installed. Chrome does not permit wildcards here, and widening the list needlessly grants more extensions access to the password-manager bridge. See [Chrome's native messaging documentation](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging) and [Bitwarden's origin list](https://github.com/bitwarden/clients/blob/main/apps/desktop/src/main/native-messaging.main.ts).

### Executable path

For the current Nixpkgs Linux package, the proxy is:

```text
${pkgs.bitwarden-desktop}/libexec/desktop_proxy
```

Nixpkgs patches the desktop app to use that immutable store path and installs the proxy under `libexec`. It also installs Bitwarden's Polkit policy under `share/polkit-1/actions`. See the [Nixpkgs Bitwarden package](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/by-name/bi/bitwarden-desktop/package.nix), [proxy-path patch](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/by-name/bi/bitwarden-desktop/set-desktop-proxy-path.patch), and [biometric setup patch](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/by-name/bi/bitwarden-desktop/dont-auto-setup-biometrics.patch).

For the official macOS bundle copied to `/Applications` or Home Manager's stable copied-app directory, the proxy is inside the bundle:

```text
/absolute/path/to/Bitwarden.app/Contents/MacOS/desktop_proxy
```

The manifest must reference the final copied application, not its mounted DMG path or a stale generation. Bitwarden can create its own manifests from the desktop UI. Declarative manifests are reasonable when the copied application path is stable.

## Manifest locations

Use exact capitalization. Gecko calls its Linux directory `native-messaging-hosts`; Chromium-family browsers use `NativeMessagingHosts`.

| Platform/browser | Per-user manifest path |
| --- | --- |
| Linux Firefox | `~/.mozilla/native-messaging-hosts/com.8bit.bitwarden.json` |
| Linux Zen | `~/.mozilla/native-messaging-hosts/com.8bit.bitwarden.json` in current Zen behavior |
| Linux Google Chrome | `~/.config/google-chrome/NativeMessagingHosts/com.8bit.bitwarden.json` |
| Linux Chromium | `~/.config/chromium/NativeMessagingHosts/com.8bit.bitwarden.json` |
| Linux Brave | `~/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts/com.8bit.bitwarden.json` |
| Linux Microsoft Edge | `~/.config/microsoft-edge/NativeMessagingHosts/com.8bit.bitwarden.json` |
| Linux Vivaldi | `~/.config/vivaldi/NativeMessagingHosts/com.8bit.bitwarden.json` |
| Linux Helium | `~/.config/net.imput.helium/NativeMessagingHosts/com.8bit.bitwarden.json` |
| macOS Firefox | `~/Library/Application Support/Mozilla/NativeMessagingHosts/com.8bit.bitwarden.json` |
| macOS Zen, Bitwarden-generated path | `~/Library/Application Support/Zen/NativeMessagingHosts/com.8bit.bitwarden.json` |
| macOS Zen, compatibility fallback | `~/Library/Application Support/Mozilla/NativeMessagingHosts/com.8bit.bitwarden.json` |
| macOS Google Chrome | `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.8bit.bitwarden.json` |
| macOS Chromium | `~/Library/Application Support/Chromium/NativeMessagingHosts/com.8bit.bitwarden.json` |
| macOS Helium | `~/Library/Application Support/net.imput.helium/NativeMessagingHosts/com.8bit.bitwarden.json` |

Mozilla and Chrome document the standard Firefox, Chrome, and Chromium locations. The additional Brave, Edge, Vivaldi, Helium, and Zen paths come directly from [Bitwarden's desktop path map](https://github.com/bitwarden/clients/blob/main/apps/desktop/src/main/native-messaging.main.ts). A [Zen macOS report](https://github.com/zen-browser/desktop/issues/13214) also records the Mozilla-directory fallback. Installing the Gecko manifest in Mozilla's directory is the safest shared choice for Firefox and Zen. Mirroring it into `Zen/NativeMessagingHosts` on macOS is harmless if both files are generated from the same source.

Home Manager already exposes the correct abstraction. `programs.firefox.nativeMessagingHosts` consumes packages containing `lib/mozilla/native-messaging-hosts`, while `programs.chromium.nativeMessagingHosts` consumes packages containing `etc/chromium/native-messaging-hosts`. See [Home Manager's Mozilla host module](https://github.com/nix-community/home-manager/blob/master/modules/misc/mozilla-messaging-hosts.nix), [Firefox module](https://github.com/nix-community/home-manager/blob/master/modules/programs/firefox/mkFirefoxModule.nix), and [Chromium module](https://github.com/nix-community/home-manager/blob/master/modules/programs/chromium.nix). The Zen Home Manager module similarly accepts `programs.zen-browser.nativeMessagingHosts`; in signed macOS mode it deliberately uses Home Manager's Mozilla host directory. [Zen browser flake package module](https://github.com/0xc000022070/zen-browser-flake/blob/master/hm-module/package.nix).

## Linux fingerprint and Polkit design

Bitwarden's Linux biometric implementation does not call a fingerprint reader directly. It holds the vault unlock key in a protected in-memory secret, asks Polkit to authenticate the current desktop user, and releases the key only after authorization. It uses a D-Bus-name subject so the check remains tied to the requesting process even across sandbox or PID namespaces. [Bitwarden Linux biometric implementation](https://github.com/bitwarden/clients/blob/main/apps/desktop/desktop_native/biometric/src/linux.rs).

Install Bitwarden's policy unchanged:

```xml
<action id="com.bitwarden.Bitwarden.unlock">
  <defaults>
    <allow_any>no</allow_any>
    <allow_inactive>no</allow_inactive>
    <allow_active>auth_self</allow_active>
  </defaults>
</action>
```

This permits an active local user to authenticate as themselves. It does not grant unattended authorization. The complete reviewed policy is in [Bitwarden's source](https://github.com/bitwarden/clients/blob/main/apps/desktop/resources/com.bitwarden.desktop.policy).

The NixOS design is:

1. Expose the `fprintd` D-Bus service and systemd unit.
2. Let `services.fprintd.enable` add `pam_fprintd.so` as a `sufficient` authentication method across the generated PAM services.
3. Install the upstream Bitwarden policy at `/etc/polkit-1/actions/com.bitwarden.Bitwarden.policy` or otherwise into Polkit's action search path.
4. Run a graphical Polkit authentication agent in the desktop session.
5. Enroll the user interactively with `fprintd-enroll` and verify with `fprintd-verify`.

`services.fprintd.enable = true` intentionally enables fingerprint authentication for generated PAM services such as sudo, login, greetd, Polkit, and screen lockers. NixOS declares the fingerprint rule as `sufficient`: a matching print can complete authentication, while failure continues through the existing PAM stack to password authentication. The configuration retains fprintd's upstream defaults of three attempts and a 30-second timeout. PAM authentication is serialized, so applications that do not run separate authentication stacks cannot accept a password and fingerprint at the same instant. The relevant behavior is visible in the pinned [fprintd module](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/nixos/modules/services/security/fprintd.nix), [PAM module](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/nixos/modules/security/pam.nix), [Polkit module](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/nixos/modules/security/polkit.nix), and [pam_fprintd manual](https://gitlab.freedesktop.org/libfprint/fprintd/-/blob/master/data/pam_fprintd.pod).

Fingerprint authentication cannot supply the login password to GNOME Keyring. A fingerprint-only first login or first Hyprlock unlock may therefore leave the password-encrypted Login keyring locked. Keep its password intact and enter the account password once after boot when Secret Service access is required. An empty keyring password would remove encryption and is not an acceptable workaround.

Enrollment cannot be made declarative without handling biometric templates as sensitive mutable state. Keep it a documented local action. Do not copy enrolled fingerprint data between machines.

Do not add a Polkit JavaScript rule that returns `polkit.Result.YES` for the Bitwarden action. Bitwarden's source explicitly treats any successful Polkit result as user verification, so a bypass rule turns biometric unlock into unauthenticated key release. Disabling the NixOS `pkexec` wrapper does not break this flow: the desktop app talks to Polkit over D-Bus and does not invoke `pkexec`.

Bitwarden recommends Flatpak or Snap on Linux because those formats receive its supported integration and update path. For this NixOS setup, use the unsandboxed Nixpkgs desktop package consistently with its store-path proxy and declaratively installed policy. Mixing a Flatpak desktop app with host-managed manifests is more fragile: Bitwarden documents Flatpak bridge setup separately, and its source currently creates Flatpak paths only for Firefox, Chrome, Chromium, and Edge. Snap supports only unsandboxed browser extensions. [Bitwarden biometric unlock documentation](https://bitwarden.com/help/biometrics/) and [native-messaging source](https://github.com/bitwarden/clients/blob/main/apps/desktop/src/main/native-messaging.main.ts).

Linux secure storage also requires a Secret Service implementation such as GNOME Keyring. The existing desktop keyring and Polkit agent are useful prerequisites and should remain enabled. [Bitwarden desktop feature support](https://bitwarden.com/help/desktop-app-feature-support/).

## macOS Touch ID and code identity

Use Bitwarden's official notarized universal DMG or Mac App Store build. Both are documented as supporting desktop and browser-extension biometrics. Avoid an ad-hoc-signed or locally rebuilt Bitwarden bundle for this path. Touch ID unlock depends on Keychain items and native code whose access is evaluated against macOS code-signing requirements. A changing identity can cause new prompts or lose access to existing protected items.

Bitwarden's official desktop identity uses bundle identifier `com.bitwarden.desktop` and Team ID `LTZ2PFU5D6`. The App Store entitlements also use the application group `LTZ2PFU5D6.com.bitwarden.desktop`. These values are in Bitwarden's [Electron build configuration](https://github.com/bitwarden/clients/blob/main/apps/desktop/electron-builder.json), [Developer ID entitlements](https://github.com/bitwarden/clients/blob/main/apps/desktop/resources/entitlements.mac.plist), and [App Store entitlements](https://github.com/bitwarden/clients/blob/main/apps/desktop/resources/entitlements.mas.plist). Apple's documentation explains that designated requirements identify signed code across versions and that App Store and Developer ID variants can have different requirements. See [Applying code requirements](https://developer.apple.com/documentation/security/applying-code-requirements), [TN3127: Inside Code Signing Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), and [Creating distribution-signed code for the Mac](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac).

Keep Zen in the flake's signed package mode. Repacking or modifying its application bundle invalidates the upstream signature, which can break Touch ID-related integrations, Keychain access, Gatekeeper, and other privacy controls. [Zen browser flake's macOS package-mode example](https://github.com/0xc000022070/zen-browser-flake/blob/master/examples/01a-macos-package-mode.nix).

Verify the installed bundles after activation:

```sh
codesign --verify --deep --strict "/Applications/Bitwarden.app"
spctl --assess --type execute --verbose=4 "/Applications/Bitwarden.app"
codesign -dv --verbose=4 "/Applications/Bitwarden.app"
```

Adjust the path if Home Manager copies applications elsewhere. The official Bitwarden bundle should report `Identifier=com.bitwarden.desktop`, a valid Apple or Developer ID signing chain, and `TeamIdentifier=LTZ2PFU5D6`. Verify Zen with the same first two commands against its final application path.

## Required application settings

After the system pieces are installed:

1. Start Bitwarden Desktop, sign in, and unlock it.
2. In desktop settings, enable unlock with system authentication or biometrics.
3. If the installed release presents **Allow browser integration**, enable it. If it presents **Require verification for browser integration**, keep that verification enabled.
4. In each Bitwarden browser extension, open **Settings > Account security > Unlock with biometrics**.
5. Accept the native-application permission request, approve the extension in the desktop app, and complete the operating-system authentication prompt.
6. Enable **Ask for biometrics on launch** only if that launch behavior is desired.

Bitwarden changes the exact settings labels as its integration evolves, so the installed release's UI is authoritative. Do not declaratively edit Bitwarden's internal `data.json` or set undocumented environment overrides to bypass the approval handshake. The documented setup sequence is in [Unlock with biometrics](https://bitwarden.com/help/biometrics/).

On Linux, Bitwarden requires one master-password or PIN unlock after the desktop application restarts before browser biometric unlock becomes available. The desktop process must remain running for browser integration. Autostarting it is appropriate, but it must not be made an always-unlocked service. On macOS, a home path longer than 104 characters can exceed the native Unix-socket path limit. [Bitwarden biometric troubleshooting](https://bitwarden.com/help/biometrics/).

Bitwarden notes that Chromium browsers may require **Allow access to file URLs** on the extension-management page. That permission broadens extension access to local `file:` pages. Leave it disabled unless native messaging demonstrably fails and re-test after browser or extension updates rather than enforcing it globally.

## Security properties to retain

The browser and desktop app establish an encrypted session over native messaging. Current Bitwarden source creates an application-specific RSA key, exchanges an encrypted session secret, checks message freshness, and associates biometric unlock with the matching account. See [browser native-messaging background](https://github.com/bitwarden/clients/blob/main/apps/browser/src/background/nativeMessaging.background.ts) and [desktop biometric message handler](https://github.com/bitwarden/clients/blob/main/apps/desktop/src/services/biometric-message-handler.service.ts).

Those controls do not replace local hardening:

- Keep the manifest allowlists exact. Never use wildcard origins or unrelated extension IDs.
- Keep the desktop app, browser, and extension on supported, patched releases.
- Preserve Bitwarden's desktop approval and operating-system authentication prompts.
- Keep a finite vault timeout and require the master password after restart as designed.
- Do not weaken the Polkit action or grant it to inactive or arbitrary sessions.
- Restrict manifest files to user or root ownership as appropriate; they must not be writable by untrusted users.
- Keep the Bitwarden desktop process in the user's graphical session, not as a privileged system service.

## Validation checklist

Linux:

```sh
fprintd-verify
pkaction --action-id com.bitwarden.Bitwarden.unlock --verbose
test -x /nix/store/...-bitwarden-desktop-*/libexec/desktop_proxy
jq . ~/.mozilla/native-messaging-hosts/com.8bit.bitwarden.json
```

Also inspect the actual Chromium-family browser directory being used. Confirm the manifest's `path` exists after a Nix generation switch, then exercise unlock independently in Firefox, Zen, and Chromium. Lock the desktop vault and verify that the extension cannot silently retrieve an unlock key. Restart Bitwarden and verify that the required first unlock is enforced.

macOS:

```sh
codesign --verify --deep --strict "/path/to/Bitwarden.app"
spctl --assess --type execute --verbose=4 "/path/to/Bitwarden.app"
plutil -lint "$HOME/Library/Application Support/Mozilla/NativeMessagingHosts/com.8bit.bitwarden.json"
```

Then test Firefox, Zen, and the chosen Chromium browser separately. Confirm that the native-host prompt names Bitwarden, desktop approval is required on first connection, Touch ID is presented by macOS, and a rejected Touch ID prompt leaves the browser vault locked.

## Known limitations

- Firefox ESR is outside Bitwarden's supported browser set.
- Zen is not named in Bitwarden's browser support table. Its native-host lookup has changed across releases, so both Linux and macOS need regression tests after Zen updates.
- Flatpak and Snap add sandbox-specific bridge rules. They should not be mixed casually with the unsandboxed Nix browser configuration.
- Chromium-family config directories differ by vendor. A manifest in Chrome's directory is not guaranteed to cover Helium, Brave, Chromium, or other derivatives.
- Browser biometrics still depends on a running, signed-in desktop app and the operating system's local authentication stack. It is not WebAuthn and does not move the vault key into the fingerprint sensor or Secure Enclave.
- A fingerprint or Touch ID unlock is convenience authentication for a local session. The Bitwarden master password and recovery material remain essential.
