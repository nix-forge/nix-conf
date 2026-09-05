# Wootility 80HE research

## Conclusion

Install Wootility 5.4.1 on both hosts, but do not start it at login and do not
enable Wooting Background Service by default. The keyboard stores its normal
profiles onboard, so Wootility can stay closed outside configuration and
firmware work. This avoids paying the memory and CPU cost of an Electron app
that is not doing anything useful.

The NixOS desktop should use the Wootility and udev support already in
nixpkgs. The repository's evaluated `pkgs.wootility.version` is 5.4.1, and the
nixpkgs `hardware.wooting.enable` option installs both `pkgs.wootility` and
`pkgs.wooting-udev-rules`. A second Linux package in nixpkgs-personal would
duplicate maintained upstream work. [The current nixpkgs module is only those
two assignments](https://github.com/NixOS/nixpkgs/blob/cfcd1628672a7e89d65cd6bc9b33bd2bfc223981/nixos/modules/hardware/wooting.nix#L10-L13),
and [the current package is Wootility
5.4.1](https://github.com/NixOS/nixpkgs/blob/cfcd1628672a7e89d65cd6bc9b33bd2bfc223981/pkgs/by-name/wo/wootility/package.nix#L8-L18).

The Apple Silicon laptop does need a personal package because nixpkgs marks
its Wootility package Linux-only. Package Wooting's arm64 DMG without changing
the application bundle. Generic fixup, wrapping the executable inside the
bundle, or editing `Info.plist` would invalidate Wooting's signature. Put any
command-line symlink outside `Wootility.app`, keep `dontFixup = true`, and
install it through the existing shared Home Manager module.

For routine edits, `https://wootility.io` in an up-to-date Chromium browser is
the safer first choice if it detects the keyboard. Keep the installed desktop
app for offline use, firmware recovery, and cases where the browser cannot use
WebHID. Wooting calls the web edition fast, secure, and lightweight, but only
documents Chromium-family browsers. Firefox and Safari do not work. [Wooting's
download page describes the two editions](https://wooting.io/wootility), and
[its troubleshooting guide documents the permission prompt and supported
browsers](https://help.wooting.io/article/92-wootility-doesnt-detect-my-wooting-keyboard#wootility-web).
Helium is Chromium-based but is not one of Wooting's named supported browsers,
so the native app remains the dependable path on these hosts.

## Release and artifacts

Wootility 5.4.1 is the current stable release as of 4 September 2026. Wooting
released it on 13 July 2026 as a fix for Background Service updating. The 5.4
series adds automatic profile linking, guided restore, and Advanced Key
presets. Its firmware notes also include an 80HE lock-up fix. [The 5.4.1
changelog lists the release, downloads, and
changes](https://wooting.io/wootility/changelogs/5.4.1).

The official update metadata publishes SHA-512 digests and sizes. The Nix
SHA-256 values below were independently calculated from the same first-party
files and agree with the current nixpkgs Linux package.

| Host | First-party artifact | Size | Nix SHA-256 |
| --- | --- | ---: | --- |
| NixOS x86_64 | [`Wootility-5.4.1.AppImage`](https://wootility-updates.ams3.cdn.digitaloceanspaces.com/wootility-linux/Wootility-5.4.1.AppImage) | 192,619,636 bytes | `sha256-QqkkfLi0teDH5E0mm4hnY42msgE/z1RV1Rl4+Tt+TaQ=` |
| macOS arm64 | [`Wootility-5.4.1-arm64.dmg`](https://wootility-updates.ams3.cdn.digitaloceanspaces.com/wootility-mac/Wootility-5.4.1-arm64.dmg) | 135,780,240 bytes | `sha256-9237eJ7PzSWkJ7mSnzwJV040YnC3V5nOtX5UtuxiW6w=` |

The controlling machine-readable files are Wooting's
[`latest-linux.yml`](https://wootility-updates.ams3.cdn.digitaloceanspaces.com/wootility-linux/latest-linux.yml)
and
[`latest-mac.yml`](https://wootility-updates.ams3.cdn.digitaloceanspaces.com/wootility-mac/latest-mac.yml).
Do not package the floating download redirect. Pin the versioned CDN URL and
hash so a compromised or changed response cannot silently alter a rebuild.

Wootility v5 supports the 80HE and every older Wooting keyboard. Version 5.0
also introduced the coherent navigation, profile manager, tooltips, quick
settings, and 80HE Light Indicator controls that make v5 the right UI rather
than the older v4 branch. [Wooting's v5.0 release notes describe the redesign
and 80HE support](https://wooting.io/wootility/changelogs/5.0.0).

## Linux device access

Do not run Wootility or a browser as root. Do not add the user to the `input`
group. Either action grants far more access than this keyboard needs.

Wooting's current Linux instructions cover legacy vendor `03eb` product IDs
and all devices under its newer vendor ID `31e3`. The Wooting 80HE is vendor
`31e3`, base product `1400`; its alternative gamepad modes use `1401` and
`1402`. [Wooting's maintained SDK defines those
IDs](https://github.com/WootingKb/wooting-rgb-sdk/blob/98364bcd85aa267ee1cd657197f5d886175251f1/src/wooting-usb.c#L34-L57).

The official example sets mode `0660`, group `input`, and `uaccess`. Nixpkgs
deliberately keeps only `TAG+="uaccess"` for both `hidraw` and `usb`. That is a
better policy here. systemd-logind grants an ACL to the active local session,
while users in a broad input-reading group do not receive permanent access.
[Wooting explains its full rule and permission
model](https://help.wooting.io/article/147-configuring-device-access-for-wootility-under-linux-udev-rules),
and [nixpkgs carries the reduced
rules](https://github.com/NixOS/nixpkgs/blob/cfcd1628672a7e89d65cd6bc9b33bd2bfc223981/pkgs/by-name/wo/wooting-udev-rules/wooting.rules#L1-L16).

Use `hardware.wooting.enable = true` rather than copying the rules into this
repository. This also keeps restore and alternate device modes working. A
rule narrowed only to product `1400` looks tidier but can fail when firmware
changes the product ID during update or restore.

The upstream AppImage's desktop entry requests `--no-sandbox`. The nixpkgs
wrapper removes that flag and supplies the Wayland and input-method flags when
`NIXOS_OZONE_WL` and `WAYLAND_DISPLAY` are set. Keep the nixpkgs wrapper rather
than placing the raw AppImage in `home.packages`. [The package's wrapper and
desktop-entry rewrite are visible
upstream](https://github.com/NixOS/nixpkgs/blob/cfcd1628672a7e89d65cd6bc9b33bd2bfc223981/pkgs/by-name/wo/wootility/package.nix#L20-L40).

## macOS provenance

The 5.4.1 Apple Silicon DMG was mounted read-only and checked before packaging:

- `Wootility.app` contains a thin arm64 executable and declares macOS 11.0 as
  its minimum version.
- `codesign --verify --deep --strict` succeeds.
- Gatekeeper accepts it as a notarized Developer ID application.
- The signer is `Developer ID Application: Wooting Technologies B.V.
  (35RZSMAL44)`, Team ID `35RZSMAL44`, and the notarization ticket is stapled.
- The hardened-runtime signature has only the JIT entitlement expected by an
  Electron application.

Those checks bind the package to Wooting's Apple identity in addition to the
fixed Nix hash. Preserve the bundle byte-for-byte with `cp -a`. No udev rule or
privileged helper is required for ordinary USB HID access on macOS.

The bundle contains generic camera, microphone, and Bluetooth usage strings,
and it permits arbitrary network loads in App Transport Security. A USB
Wooting 80HE does not need those three privacy permissions. Do not grant them
if macOS prompts unexpectedly.

## Security and privacy limits

Wootility is proprietary software. Wooting does not publish the application
source in its GitHub organization, and nixpkgs classifies the binary as
`lib.licenses.unfree`. Keep that metadata rather than assigning a license from
one of Wooting's separate open-source SDKs. [The nixpkgs package records the
unfree license and Linux-only support](https://github.com/NixOS/nixpkgs/blob/cfcd1628672a7e89d65cd6bc9b33bd2bfc223981/pkgs/by-name/wo/wootility/package.nix#L45-L56).

The native 5.4.1 artifact bundles Electron 37.6.1 and Chromium 138. Electron
37 reached end of support on 13 January 2026, six months before Wooting
released Wootility 5.4.1. This is the strongest reason to prefer Wootility Web
inside a current Chromium build for normal configuration. [Electron's release
schedule gives the end-of-life date](https://releases.electronjs.org/schedule),
and [Electron 37.6.1 identifies its Chromium and Node
versions](https://releases.electronjs.org/release/v37.6.1).

Static inspection of the pinned artifact found further desktop hardening gaps.
Its local `BrowserWindow` disables context isolation, enables `webviewTag`,
automatically approves HID access for Wooting vendor IDs, and permits local
network requests. It does disable Node integration, rejects non-listed device
vendors, and sends new windows to the external browser. Electron recommends a
current framework, context isolation, renderer sandboxing, explicit permission
handling, and strict navigation controls. [Electron's security checklist is
the relevant upstream baseline](https://www.electronjs.org/docs/latest/tutorial/security).
Nix packaging can preserve Chromium's process sandbox on Linux, but it cannot
repair renderer settings inside this closed application.

The same artifact initializes PostHog with autocapture, page-view, and
page-leave collection. It also initializes Sentry with normal session replay
off and a 10 percent replay sample when an error occurs. Wooting's policy says
it collects IP address, browser and device data, page interactions, and data
needed for software features, and may use personal information for product
development and marketing. It also says that Do Not Track does not change its
collection. [The current Wooting privacy policy states those
terms](https://wooting.io/policies/privacy-policy).

There is no Nix-side switch that can safely remove the telemetry without
rewriting the signed app or risking breakage of Wootility's API calls. The
practical containment is simple: do not log in unless account-backed features
are wanted, close Wootility after use, and leave the optional service off.

## Updates and Background Service

Wootility checks for application updates at launch but does not download or
install them automatically. An in-app replacement is the wrong update path
for a Nix-store application. Update the nixpkgs input for Linux and the pinned
nixpkgs-personal source for macOS, then rebuild. The fixed source hash is part
of the security boundary.

Wooting Background Service is separate from the editor. Version 5.4 uses it to
watch the foreground application and switch keyboard profiles. Earlier 80HE
features can show CPU use, volume, Discord mute state, and notifications on
the Light Indicator. Wooting says Wootility itself can close once the service
is running. [The current setup and runtime behavior are documented in the
5.4.1 notes](https://wooting.io/wootility/changelogs/5.4.1#automatic-profile-switching-with-app-linking),
and [the original 80HE service features are documented in
5.2.1](https://wooting.io/wootility/changelogs/5.2.1#80he-introducing-background-service).

Do not install or auto-start the service during Nix activation. It expands
the amount of desktop activity Wooting software can observe and consumes
resources continuously. If App Linking or a live Light Indicator is wanted
later, enable the service deliberately in Wootility, verify the installed
service and its startup entry, and keep Wootility closed. This is both faster
and narrower than leaving the full editor running.

## Verification

Evaluation and package checks can run anywhere. Per this repository's
`AGENTS.md`, run the full desktop closure build on `desktop`, normally through
`just desktop-build` from another host.

After deployment:

1. Confirm both evaluations report Wootility 5.4.1.
2. On NixOS, confirm the installed rule contains `TAG+="uaccess"` and no
   `GROUP="input"`, then check the active session receives an ACL on the
   Wooting `hidraw` device.
3. Launch from the application menu without `sudo`. The device indicator
   should turn green and the 80HE should appear by name.
4. On macOS, run `codesign --verify --deep --strict` and `spctl --assess` on
   the installed `Wootility.app`; both should still pass.
5. Duplicate or export a profile before the first firmware change. Test a
   harmless setting, write it to the keyboard, restart Wootility, and confirm
   the onboard profile remains.
6. Use the stable Wootility and firmware channels. A firmware update should
   use a direct cable and stable USB power. Wootility includes the firmware
   available when it shipped, which gives it an offline recovery path if its
   firmware service cannot be reached. [Wooting documents the bundled
   fallback](https://help.wooting.io/article/146-error-during-update-or-restore#firmwaredata).

The last device-connect and profile-write checks require the physical 80HE.
They cannot be proven by a Nix build alone.
