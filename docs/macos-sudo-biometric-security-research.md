# macOS sudo biometric security research

Research date: 2026-09-02

Remediation applied: 2026-09-02. The machine now uses the best practical local
security profile from this report. The live sudo PAM file contains only Apple's
`pam_tid.so`, `ignoreArd` is false, and the Codex capture service that triggered
the observed-screen restriction was stopped. A live sudo test completed with
Touch ID mechanism 1.

## Decision

The strictest configuration is password-only sudo with Apple's screen-observation
guard left intact. That means no Touch ID, no Apple Watch PAM plug-in, no
bootstrap reattachment, and no `ignoreArd` override. It has the fewest accepted
credentials and loads no third-party code into sudo's authentication process.
The cost is frequent password entry, which exposes the password to shoulder
surfing and any local software capable of capturing keystrokes.

For this single-user Mac, the best practical configuration is Apple's own
`pam_tid.so` with password fallback, `ignoreArd` absent, and the two third-party
modules disabled. Touch ID keeps the
account password out of routine sudo interactions, performs fingerprint matching
inside the Secure Enclave, and requires an intentional touch. macOS still forces
the password after restart or logout, after 48 hours without an unlock, and after
five failed fingerprint matches. [Apple's biometric architecture](https://support.apple.com/guide/security/biometric-security-sec067eb0c9e/web),
[Touch ID password conditions](https://support.apple.com/en-us/105095)

That practical recommendation will not provide Touch ID while Codex or another
application is recording the screen. Keeping Touch ID available during trusted
local capture requires `ignoreArd = true`. This is a real reduction in defense,
not a harmless compatibility flag. It is reasonable only if the user accepts
that tradeoff, keeps Screen Sharing and Remote Management off, limits Screen &
System Audio Recording permission to trusted applications, and never approves
an unexpected sudo prompt.

## Recommendation matrix

| Profile | `touchIdAuth` | `watchIdAuth` | `reattach` | `ignoreArd` | Assessment |
| --- | --- | --- | --- | --- | --- |
| Strictest, smallest attack surface | `false` | `false` | `false` | absent or `false` | Password is the only active sudo credential on this Mac. |
| Best practical local security | `true` | `false` | `false` | absent or `false` | Uses Apple's module and Secure Enclave with password fallback. |
| Best practical security with tmux | `true` | `false` | `false` | absent or `false` | Use password inside persistent or remote tmux, or run Touch ID sudo outside it. The pinned reattachment module has an unsafe SSH guard. |
| Touch ID while trusted capture stays open | `true` | `false` | `false` | `true` | Meets the requested workflow but disables Apple's screen-observation safeguard. |
| Configuration before remediation | `true` | `true` | `true`, without `ignore_ssh` | `true` | Maximum convenience and the widest authentication and privileged-code exposure. |

`watchIdAuth = false` refers to the separate `pam-watchid` package. The native
macOS authorization path may still offer an Apple Watch if "Use your Apple Watch
to unlock apps and your Mac" is enabled in System Settings. The pinned
nix-darwin option documentation explicitly says its Touch ID setting can also
allow Apple Watch approval. Turn off that System Settings switch if the desired
policy is Touch ID or password only. [Pinned nix-darwin PAM module](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/security/pam.nix#L28-L46)

## What was active during diagnosis

Read-only inspection on macOS 26.6.2 found this authentication order:

```text
# /etc/pam.d/sudo_local
auth optional   /nix/store/...-pam_reattach-1.3/lib/pam/pam_reattach.so
auth sufficient pam_tid.so
auth sufficient /nix/store/...-pam-watchid-2-unstable-2024-12-24/lib/pam_watchid.so

# /etc/pam.d/sudo
auth include    sudo_local
auth sufficient pam_smartcard.so
auth required   pam_opendirectory.so
```

The flake pins nix-darwin at `4cff07de` and Nixpkgs at `4382ed2b`. The actual
third-party binaries are `pam_reattach` 1.3 and `pam-watchid` revision
`bb9c6ea6`, packaged as `2-unstable-2024-12-24`. Both installed binaries have
only ad hoc linker signatures, with no Team ID. Nixpkgs fetches fixed source
revisions and places the results at content-derived, non-user-writable store
paths. That makes silent replacement by an ordinary process difficult. It does
not establish that the source is correct or that the code received an Apple
security review. In contrast, the installed `/usr/lib/pam/pam_tid.so.2` is a
universal Apple platform binary signed by the macOS Software Signing authority.
[Pinned `pam_reattach` package](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/by-name/pa/pam-reattach/package.nix),
[pinned `pam-watchid` package](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/by-name/pa/pam-watchid/package.nix),
[Nix multi-user security model](https://releases.nixos.org/nix/nix-2.20.3/manual/installation/multi-user.html)

Before remediation, the preference database contained
`com.apple.security.authorization.ignoreArd = 1`. The repository writes it
through nix-darwin's `CustomUserPreferences`, which runs `defaults write` as the
primary user. This is not the same installation mechanism as a system-scoped
configuration profile, even though it uses the profile payload's domain and key.
[Pinned nix-darwin defaults writer](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults-write.nix#L8-L18)

## PAM makes these alternatives, not extra factors

Both biometric lines use PAM's `sufficient` control flag. A successful module
ends the authentication chain and grants the request if no earlier required
module failed. A failed sufficient module is ignored and PAM continues to the
next method. The `optional` result from `pam_reattach` never decides whether
authentication succeeds. [Apple OpenPAM chain semantics](https://github.com/apple-oss-distributions/OpenPAM/blob/main/openpam/doc/man/pam.conf.5#L98-L127)

The active flow is therefore:

1. `pam_reattach` attempts to move sudo into the logged-in user's Aqua bootstrap
   namespace.
2. A successful `pam_tid` request grants sudo immediately.
3. If it does not succeed, a successful `pam-watchid` request grants sudo
   immediately.
4. If neither succeeds, Apple's smart-card module gets a chance, then
   `pam_opendirectory` requires the account password.

Touch ID plus Apple Watch plus password is not three-factor authentication. It
is an OR relationship. Adding an accepted method expands the ways an
authentication can succeed. NIST treats a locally verified biometric bound to a
physical authenticator as a biometric activation factor, but that does not
change the PAM composition into password plus biometric MFA. [NIST SP 800-63B,
use of biometrics](https://pages.nist.gov/800-63-4/sp800-63b.html#use-of-biometrics)

For a US federal or similarly regulated build, the answer is stricter than the
personal-Mac recommendation. NIST's example mSCP/STIG guidance does not treat
Touch ID or Watch unlock as a verified SP 800-63 authenticator and disables
screen-sharing services. That is a compliance decision, not evidence that
Apple's mechanisms are cryptographically weak. [NIST mSCP example guidance](https://pages.nist.gov/macos_security/guidance-example.pdf)

The fallback behavior is fail-safe for availability. Cancelling or failing the
Touch ID and Watch prompts still reaches the password module. It is not fail-safe
against a bug that incorrectly returns `PAM_SUCCESS`, because either sufficient
module can authorize sudo on its own.

## Touch ID

Touch ID is the strongest convenience option here. The sensor sends its scan to
the Secure Enclave over an authenticated and encrypted channel. The Secure
Enclave creates and stores an encrypted mathematical template, performs the
comparison, and returns only the match result. The fingerprint image is
discarded, never sent to Apple, and not included in backups. Apple publishes a
one-in-50,000 false-match probability for one enrolled finger and limits matching
to five failed attempts before requiring the password. [Apple Platform Security](https://support.apple.com/guide/security/biometric-security-sec067eb0c9e/web),
[Apple Touch ID safeguards](https://support.apple.com/en-us/105095)

Touch ID does not eliminate the password. macOS requires it after startup,
restart, logout, a 48-hour interval, enrollment changes, and repeated failed
matches. This is good recovery and protects against indefinite biometric
guessing. It also means the security of the account still depends on a strong,
unique login password.

Apple's `pam_tid` source is materially better suited to PAM than the separate
Watch plug-in. It retrieves the PAM user, resolves that user's UID, passes the
UID to LocalAuthentication, confirms an Aqua session, avoids interactive UI in
sudo askpass mode, and asks Authorization Services for the
`com.apple.security.sudo` right. [Apple `pam_tid` source](https://github.com/apple-oss-distributions/pam_modules/blob/a8705983365bdb9b5c6c1ff5fd55c321dc01deec/modules/pam_tid/pam_tid.c#L47-L157)

The main nontechnical weakness is that a fingerprint is not secret or
revocable. Physical coercion and latent-print attacks are different risks from
password guessing. Users with that threat model should choose password-only
sudo.

## Apple Watch

Apple's native Watch design is cryptographically serious. The Mac and Watch
must use the same Apple Account with two-factor authentication. The Watch must
have a passcode, be unlocked, and remain near the Mac. Apple documents BLE
setup, a secure STS tunnel, peer-to-peer Wi-Fi ranging, a rolling random 32-byte
unlock secret, and a two-to-three-meter distance requirement. Admin approvals
require a double-click on the Watch side button. Wrist Detection locks the Watch
soon after removal. [Apple automatic unlock security](https://support.apple.com/guide/security/sec6ab47ebfc/web),
[watchOS security](https://support.apple.com/guide/security/secc7d85209d/web),
[Apple Watch approval requirements](https://support.apple.com/en-ie/102442)

The tradeoff is a larger trust boundary. Sudo approval now depends on the paired
Watch, its passcode and wrist state, Apple Account pairing, radios, and the Mac's
companion-authentication code. The explicit double-click is useful evidence of
intent, but vague or unexpected Watch prompts can still be approved by mistake.

The separate `pam-watchid` module is hard to justify on this Mac unless Apple's
native sudo path cannot meet a real clamshell use case. Its pinned source calls
`deviceOwnerAuthenticationWithBiometricsOrCompanion` on macOS 15 and newer. That
policy accepts either biometrics or a companion device. The module does not read
the PAM user or bind the request to a PAM UID, and its default prompt says only
"perform an action that requires authentication." It returns `PAM_IGNORE` on
LocalAuthentication errors and `PAM_SUCCESS` on a positive result. This is not
evidence of a known exploit, but it is weaker account binding and poorer prompt
context than Apple's `pam_tid` implementation. [Pinned `pam-watchid` source](https://github.com/mostpinkest/pam-watchid/blob/bb9c6ea62207dd9d41a08ca59c7a1f5d6fa07189/Sources/pam-watchid/pam_watchid.swift),
[Apple companion policy](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthenticationwithbiometricsorcompanion)

## Bootstrap reattachment

`pam_reattach` exists because tmux and GNU Screen can remain attached to an old
bootstrap namespace that lacks the current login session's GUI services. Version
1.3 asks launchd for the user's Aqua bootstrap port and replaces the current
process's bootstrap port before later PAM modules run. It is correctly marked
`optional`, so a compatibility failure falls back to the remaining methods.
[Upstream `pam_reattach` design](https://github.com/fabianishere/pam_reattach/tree/v1.3),
[reattachment implementation](https://github.com/fabianishere/pam_reattach/blob/v1.3/src/reattach.c)

The module still runs native C code in sudo's privileged authentication path and
uses private XPC details. `optional` prevents a normal error from locking out the
user; it does not sandbox the code or limit the effect of a memory-safety flaw.
Disable it if Touch ID is not needed inside persistent tmux or Screen sessions.

Upstream documents an `ignore_ssh` option for an important reason. A tmux pane
may originate in a remote login that `pam_tid` does not recognize as remote.
Without the option, reattachment can expose local GUI authentication prompts to
a sudo request started through SSH. The current nix-darwin boolean emits no
`ignore_ssh` argument. [Upstream remote-session warning](https://github.com/fabianishere/pam_reattach/blob/v1.3/README.md#usage),
[pinned nix-darwin generated rule](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/security/pam.nix#L63-L68)

Do not add `ignore_ssh` to the pinned 1.3 module as-is. Its C loop compares the
array index with `sizeof(ssh_env_vars)`, which is the byte size of the array,
instead of the number of elements. On arm64, it can read beyond the three-entry
array when no SSH variable is set. This is a concrete memory-safety bug in code
loaded by sudo. The secure response is to disable `reattach` and use password
authentication inside tmux. Patching and testing the loop would be required
before considering the SSH guard. [Pinned `pam_reattach` authentication code](https://github.com/fabianishere/pam_reattach/blob/b144392c7c98631dd074fddc5f9344286587004b/src/pam.c#L37-L56)

## `ignoreArd` and screen capture

Apple normally disables Touch ID, Apple Watch, and smart-card approval when the
screen is being shared or recorded. NIST's macOS Security Compliance Project
records the SecurityAgent message: "Screen is being watched, no Touch ID, Watch
or SmartCard support is allowed." Its supplemental smart-card guidance gives
`ignoreArd` as the override, including a configuration-profile payload with the
same domain and key as this repository. The guidance is supplemental. It is not
a requirement to turn the override on. [NIST mSCP screen-sharing guidance](https://github.com/usnistgov/macos_security/blob/afc00effea595336360ad562ed8d49e1cdeaa510/src/mscp/data/rules/supplemental/supplemental_smartcard.yaml#L269-L288)

`ignoreArd = true` does not grant Screen Recording permission, enable Screen
Sharing, or let a viewer fake a fingerprint. It removes SecurityAgent's refusal
to use these authenticators while observation is active. The remaining attack
requires more capability or user participation:

- A passive screen-recording process can observe the workflow but cannot by
  that permission alone type a privileged command or manufacture a Touch ID
  match.
- A remote-control session, or malware with input-control or command-execution
  ability, can initiate a sudo request and present an authentication prompt.
- Touch ID still needs the enrolled finger. Watch approval still needs an
  unlocked nearby Watch and the side-button gesture. The danger is authorization
  confusion: the user may approve a request whose initiating command or remote
  operator they cannot see clearly.

Apple does not publish the rationale for this exact check in the cited material.
Treating it as protection against remote or recorded authorization confusion is
an inference from the behavior and threat sequence, not an Apple statement.

The current Codex capture is a trusted local compatibility case, but the
preference is global for the user. It cannot distinguish Codex from a real
remote-support session or another approved recorder. This is why the most secure
choice is to remove the override and close the capturing application when Touch
ID is needed.

## Nix and PAM trust

Nix helps in two useful ways. The flake pins exact source revisions, and the
multi-user store prevents an ordinary user process from overwriting the active
module in place. The `/etc/pam.d/sudo_local` symlink is also root-managed and
read-only. Those properties improve reproducibility and resist local tampering.

They do not make a third-party PAM module equivalent to an Apple system module.
A malicious upstream revision, compromised trusted binary cache, unsafe Nix
builder, compiler defect, or bug in the module can still produce privileged code.
Only trusted Nix users may select arbitrary binary caches in the standard
multi-user model, so the trusted-user and substituter configuration remains part
of this boundary. [Nix multi-user mode](https://releases.nixos.org/nix/nix-2.20.3/manual/installation/multi-user.html)

Apple's OpenPAM implementation dynamically loads each configured module into
the authentication process. Its loader can retry after disabling library
validation for a module that failed that check. A Nix store path and ad hoc
signature therefore do not create a sandbox or Apple trust decision around the
module. [Apple OpenPAM module loader](https://github.com/apple-oss-distributions/OpenPAM/blob/main/openpam/lib/openpam_dynamic.c#L57-L123)

For authentication code, a small dependency set is worth more than feature
redundancy. Prefer `pam_tid.so`, which ships with macOS, and remove both
third-party modules from the active path.

## Proposed target configurations

For strictest security, manage an empty `sudo_local` and remove the stored
`ignoreArd` preference. For the recommended practical profile, the effective
PAM addition should be only:

```text
auth sufficient pam_tid.so
```

Inside a persistent tmux or SSH-originated pane, accept password fallback or run
the Touch ID sudo command in a fresh local terminal. Do not enable the pinned
`pam_reattach` 1.3 `ignore_ssh` path until its out-of-bounds loop has been
patched and tested.

If uninterrupted Touch ID during Codex capture matters more than the
screen-observation guard, keep `ignoreArd = true` but still remove the separate
Watch and reattachment modules. Before any real screen-share or remote-support
session, stop captured terminals or turn the override off.

Removing the Nix attribute alone will not delete a value already written by
`defaults`. The preference must be deleted once with:

```sh
defaults delete com.apple.security.authorization ignoreArd
```

No active configuration was changed during this research.
