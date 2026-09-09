# YubiKey 5 support on Linux and macOS

Reviewed: 2026-09-08. Scope: YubiKey 5 USB-C devices, firmware 5.8,
NixOS desktop support, and macOS support.

## Answer

Both platforms support the standard USB interfaces used by YubiKey 5 devices.
Linux needs user access to the HID interfaces and PC/SC for smart-card
applications. macOS supplies the platform interfaces, but may ask the user to
approve a newly connected USB key. Install the `ykman` CLI for inspection and
management; Yubico Authenticator is an optional GUI. These provide device support;
account enrollment and operating-system login policies are separate choices.

## Findings and sources

### Firmware and management software

Yubico's [firmware matrix](https://docs.yubico.com/hardware/yubikey/yk-tech-manual/yk5-firmware-overview.html)
lists firmware 5.8 for USB-C forms including 5C NFC and 5C Nano. It retains
FIDO U2F, FIDO2/WebAuthn, OATH, OpenPGP, and PIV. Confirm the exact model and
firmware from the device instead of inferring them from packaging shorthand.
YubiKey firmware cannot be upgraded after manufacture.

The same matrix identifies features that require partner support. Firmware 5.8
adds FIDO capabilities such as conditional mediation primitives and FIDO over
CCID. Their availability on a key does not establish that every browser or
application uses them.

The [`ykman` release list](https://developers.yubico.com/yubikey-manager/Releases/)
shows 5.9.2 as the latest CLI release on the review date. Its version is
independent of device firmware. The reviewed sources do not establish one minimum
CLI version covering every firmware 5.8 feature. Prefer the current maintained
package and test the needed operations. The old YubiKey Manager GUI is no longer
supported; Yubico recommends
[Yubico Authenticator](https://www.yubico.com/support/download/yubikey-manager/).

### Interfaces and platform requirements

| Use | Interface | Platform requirement |
| --- | --- | --- |
| Browser security keys and passkeys | FIDO over USB HID | WebAuthn-compatible browser and user access to the device |
| OATH codes, PIV certificates, OpenPGP | USB CCID smart card | Linux PC/SC service and reader driver; macOS platform support |
| OTP slot output | USB keyboard | Standard keyboard support; management permissions can differ |

These are source claims from Yubico's
[USB interface documentation](https://docs.yubico.com/hardware/yubikey/yk-tech-manual/yk5-physical-attributes.html).
Yubico's [Authenticator documentation](https://developers.yubico.com/yubioath-flutter/)
explicitly requires Linux `pcscd` for smart-card communication and notes that HID
permissions may need configuration. On NixOS, configure these through system
modules rather than following another distribution's installation commands.

On Apple silicon laptops, unlock the Mac and approve the new key if prompted.
[Apple's accessory instructions](https://support.apple.com/en-us/102282)
explain this approval; changing the global policy to always allow accessories
is unnecessary for approving an individual key.

Yubico Authenticator's
[macOS installation guide](https://docs.yubico.com/software/yubikey/tools/authenticator/auth-guide/installation.html)
ties Input Monitoring to OTP slot management and Screen Recording to scanning
OATH QR codes. Grant permissions when using those features.

### SSH is an additional integration

Yubico's [FIDO2 SSH guide](https://developers.yubico.com/SSH/Securing_SSH_with_FIDO2.html)
requires OpenSSH 8.2 or newer compiled with FIDO support. It states that Apple's
bundled OpenSSH lacks `libfido2` support. Select a FIDO-enabled OpenSSH build for
hardware SSH keys and check which executable is on `PATH`. A version string
alone does not establish this capability. Existing SSH policy is documented in
[the SSH module research](ssh-module-research.md).

### Password-manager and Apple Account use

Bitwarden supports hardware keys through its
[FIDO2/WebAuthn two-step login](https://bitwarden.com/help/setup-two-step-login-fido/).
In the web vault, choose Settings, Security, Two-step login, then manage the
Passkey option and register each physical key. Save the two-step recovery code
outside the vault. This method protects login; unlocking an already logged-in
vault does not require the second factor again.

[Security Keys for Apple Account](https://support.apple.com/en-us/102637)
requires at least two FIDO-certified keys during setup. On a compatible Mac,
open System Settings, the Apple Account, Sign-in & Security, Two-Factor
Authentication, then Security Keys. This feature protects Apple Account
authentication. It does not configure a YubiKey requirement for unlocking the
Passwords app or encrypted boot.

## Validation and limits

Both complete host system derivations evaluated successfully on Linux. Focused
evaluation confirmed `ykman` 5.9.2 on both hosts, and PC/SC, CCID, and Yubico udev
rules on NixOS. The Linux CLI, PC/SC package, and udev-rule package were realised
from the binary cache; `ykman --version` ran successfully. Nix formatting and
static checks passed for the changed configuration files.

The desktop uses USBGuard with a default-block policy and existing
device-specific rules. A subsequent insertion exposed a Yubico device with
OTP, FIDO, and CCID interfaces. Sysfs reported it as unauthorized, and the
USBGuard audit log confirmed the block. The host policy now includes its
reviewed descriptor hash without a port restriction. On 2026-09-09, the second
key presented the same hash and was already authorized. It exposed no USB
serial descriptor, so the rule matches identical descriptors rather than a
unique physical key. No duplicate rule was needed. USBGuard authorization is
an additional requirement beyond the HID permissions and PC/SC service.

After temporary USBGuard authorization, `ykman info` identified a YubiKey 5C
with firmware 5.8.0 and OTP, FIDO, and CCID enabled. `ykman fido info` read its
FIDO2 status successfully as the ordinary desktop user. This verifies USB HID
access for the tested key. The CLI also reported PC/SC unavailable, so it did
not verify smart-card communication.

At the subsequent check on 2026-09-09, the running desktop had `ykman` installed
and its PC/SC socket and service active. The second key also reported YubiKey
5C firmware 5.8.0, and the ordinary desktop user could read its FIDO2 status.
The initial PC/SC warning was absent, but OATH and PIV status queries failed.
The PC/SC log reported USB access denied; the USB device node still belonged
to `root:root`, while the daemon runs as `pcscd`. The installed CCID udev rule
assigns the `pcscd` group on device-add events. Reconnecting the key after
activation changed the device group to `pcscd`. Device information, FIDO2,
OATH, and PIV status queries then all succeeded as the ordinary desktop user.
After swapping back to the first key, the same four queries also succeeded
with the device authorized and its group set to `pcscd`. Both keys therefore
passed FIDO and smart-card communication checks under the active desktop
configuration, and both reported firmware 5.8.0.
The agent did not perform or observe the intervening system build and
activation. macOS runtime and browser registration and authentication remain
untested.

For an initial inspection, connect one key at a time and run these read-only
commands locally on each host:

```sh
ykman --version
ykman info
ykman fido info
ykman oath info
ykman piv info
```

[`ykman info`](https://docs.yubico.com/software/yubikey/tools/ykman/Base_Commands.html)
reports the device model, firmware, enabled interfaces, and applications.
Keep its serial number and other raw device output outside public documentation.
The protocol status commands inspect communication; they do not prove a browser
can complete registration and authentication. Test both keys in the intended
browser on both hosts after configuration is active.

## Implication for this repository

The [shared YubiKey module](../modules/shared/yubikey.nix) enables NixOS's
`programs.yubikey-manager`, which supplies the CLI, PC/SC service, CCID driver,
and Yubico udev rules. Its Darwin branch installs the CLI. Yubico Authenticator
remains an optional GUI.

Authorize each physical key through the desktop's USBGuard policy when its
descriptors are available. Validate configuration evaluation, package builds,
and physical-key operation as separate results. Choose account enrollment,
SSH key generation, and login enforcement once device communication works.
