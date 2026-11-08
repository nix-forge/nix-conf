# Security keys, password storage, and account recovery

Reviewed: 2026-09-09. Scope: personal Apple, Bitwarden, and Google accounts,
two FIDO2 security keys, and a possible future Vaultwarden migration.

## Answer

Use Bitwarden for routine password storage. Register both hardware keys with
each critical account, memorize a unique Bitwarden master passphrase, and keep
independent offline recovery records. Passwords for Apple and Google can remain
random and stored in Bitwarden because the recovery record provides access
without the vault. An Apple Passwords copy of the Bitwarden master password is
optional; it should not be the primary recovery design.

These are recommendations for balancing phishing resistance, physical loss,
and recovery. No account enrollment or recovery procedure was performed.

## Credentials and storage

| Credential | Recommended form | Routine storage | Independent recovery |
| --- | --- | --- | --- |
| Bitwarden master password | Six randomly selected words, unique | Memorize | Protected physical record |
| Apple Account password | At least 24 generated characters where accepted | Bitwarden | Protected physical record |
| Google Account password | At least 24 generated characters where accepted | Bitwarden | Protected physical record |
| Other site passwords | Unique generated passwords | Bitwarden | Encrypted vault backup |
| Computer login passwords | Separate random passphrases | Memorize | Protected physical record |
| Phone passcode and FIDO2 PINs | Separate strong secrets | Memorize | Protected physical record |

Randomly selected words can be memorable. Quotes, personal facts, and manually
invented word combinations do not provide the same randomness. The proposed
lengths are recommendations, not claims about vendor minimums. Bitwarden
explains why the [master password](https://bitwarden.com/help/master-password/)
must be strong and memorable and cannot be retrieved by its support team.

Store Apple and Google passwords in Bitwarden. Avoid putting both the
Bitwarden master password and its two-step recovery code into Apple Passwords:
someone who can read both can remove the hardware second-factor requirement.
Keeping each vault's only recovery information inside the other creates a
dependency that fails if both become inaccessible.

Use a locked safe for a paper recovery record, with another protected copy in
a separate location if practical. Include account identifiers, master password,
critical account passwords, hardware PINs, recovery codes, backup-decryption
password, and recovery instructions. Treat the record as account access, and
keep it separate from the daily key and laptop. Bitwarden's
[security readiness kit](https://bitwarden.com/resources/bitwarden-security-readiness-kit/)
describes independent recovery records.

## Enrollment sequence

### Prepare both keys

Label the keys by role and register each separately with every account.
Credentials do not automatically synchronize between hardware keys. Carry one
and keep the other securely elsewhere. See Yubico's
[passkey guidance](https://www.yubico.com/resources/glossary/what-is-a-passkey/).

For a key without a FIDO2 PIN, connect only that key and run:

```sh
ykman fido access change-pin
```

Enter the PIN in the interactive prompt. Eight randomly selected digits are a
practical recommendation; keep each key's PIN separate from account passwords.
Repeat with the second key. A FIDO2 PIN is per key, not per website. Setting it
does not guarantee every second-factor operation will request it. See the
[FIDO command guide](https://docs.yubico.com/software/yubikey/tools/ykman/FIDO_Commands.html).
The [device-support research](yubikey-research.md) covers disabling keyboard OTP
while retaining FIDO and smart-card applications.

### Google Account

In Google Account security settings, enable 2-Step Verification and register
both keys through Passkeys and security keys or the security-key enrollment
flow. Choose the external security key in the browser prompt. Give each entry
the same role label used on the physical key. Follow Google's
[security-key guide](https://support.google.com/accounts/answer/6103523?hl=en).

Save [backup codes](https://support.google.com/accounts/answer/1187538?hl=en)
offline for ordinary 2-Step Verification. Review
[recovery phone and email settings](https://support.google.com/accounts/answer/183723?hl=en).
A recovery email should have its own secure login and a recovery path that
does not depend exclusively on the primary account.

For stricter sign-in enforcement, evaluate
[Advanced Protection](https://support.google.com/accounts/answer/7519408?hl=en)
after testing the keys and required mail applications. It requires security
keys or passkeys, restricts some third-party access, and strengthens account
recovery checks. Google recommends recovery contact details. Its backup-code
documentation says downloadable backup codes are unavailable under Advanced
Protection, so do not carry over the ordinary-code recovery assumption.

### Bitwarden

In the web vault, open Settings, Security, Two-step login, then manage Passkey.
Register both physical keys. Use this FIDO2/WebAuthn method with keys whose USB
OTP interface is disabled. Keep an authenticated tab open while testing each
key in another session. See the
[two-step guide](https://bitwarden.com/help/setup-two-step-login-fido/).

Save the [two-step recovery code](https://bitwarden.com/help/two-step-recovery-code/)
outside Bitwarden. Recovery needs the account email, master password, and code;
the code does not recover a forgotten master password. After using it, restore
two-step protection and save the replacement code.

Prefer hardware keys plus offline recovery over adding email or TOTP as another
routine login alternative. Do not remove an existing working method until both
keys and the recovery record are verified. Local vault unlocking is separate
from login: use a short automatic-lock timeout and require the master password
after application restart where the client supports it.

### Apple Account

In System Settings on a Mac, open the Apple Account, Sign-in & Security,
Two-Factor Authentication, and Security Keys. Enroll both keys. Apple requires
two compatible keys and supported software; USB-C keys work with iPhone 15 and
newer. A key or trusted Apple device can authorize sign-in. Losing all trusted
devices and keys can cause permanent lockout. See
[Apple's requirements](https://support.apple.com/en-us/102637).

On supported iPhones, consider
[Stolen Device Protection](https://support.apple.com/en-us/120340)
with the security delay set to Always. This protects sensitive device and
account actions even in familiar locations.

Apple's optional [28-character recovery key](https://support.apple.com/en-us/109345)
is distinct from a physical security key and changes the recovery process.
Do not enable it casually or treat it as a replacement for keeping access to
hardware keys and trusted devices. If enabled, keep it outside iCloud.

## MFA and passkey choices

FIDO/WebAuthn resists phishing through binding authentication to the correct
site. Authenticator codes and SMS can be phished. See
[NIST's MFA guidance](https://www.nist.gov/itl/smallbusinesscyber/guidance-topic/multi-factor-authentication).
Additional enabled methods usually provide alternative routes, not cumulative
requirements. A recovery code is a deliberate offline fallback, not another
daily factor.

For ordinary sites, storing passkeys in Bitwarden is a reasonable convenience
choice. A synced passkey depends on its password manager, devices, and recovery
system. A hardware passkey stays on its key. To keep Gmail access dependent on
separate hardware, put its passkeys on the YubiKeys rather than in Bitwarden.
Google documents that [passkey login](https://support.google.com/accounts/answer/13548313?hl=en-GB)
bypasses its separate second step and does not remove existing recovery routes.

Bitwarden has two distinct settings. Passkey under Two-step login adds a second
factor. [Log in with passkey](https://bitwarden.com/help/login-with-passkeys/)
creates an alternative login that bypasses two-step login; with supported PRF
vault encryption enabled, it also decrypts without the master password.
Recommendation: start with master password plus hardware two-step login. Add
passwordless login only after deciding where that alternative credential should
live. Avoid making an Apple-synced Bitwarden login passkey part of the initial
hardware-key requirement.

For sites offering only TOTP, a separate authenticator provides separation from
the password vault. Storing lower-impact sites' passwords and TOTP together is
a convenience tradeoff. Never make the protected account's own locked vault the
only location of its second factor. OATH codes on a YubiKey remain phishable
codes; the hardware alone does not turn them into FIDO authentication.

## Vault backups and future self-hosting

Make a [password-protected encrypted export](https://bitwarden.com/help/encrypted-export/)
and retain its password independently. Account-restricted exports cannot move
to another server. Check [export coverage](https://bitwarden.com/help/export-your-data/)
for attachments, organizations, and passkeys; a vault export is not a complete
account or server backup.

Vaultwarden gives control of hosting, but adds responsibility for patching,
availability, TLS, and recovery. Keep hosted Bitwarden until restoring a test
deployment and accessing backups during an outage both work. Configure the
destination account's MFA and recovery afresh and test every client.
[Vaultwarden WebAuthn](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-U2F-%28and-FIDO2-WebAuthn%29-authentication)
depends on the HTTPS domain, so plan to enroll account-login keys for the new
server. Check current passkey-login support at migration time. Follow the
[server-backup guidance](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault)
as well as keeping portable vault exports. Store the server's own recovery
credentials somewhere accessible when that server is down.

## Validation and limits

This is source-backed guidance and a proposed setup sequence. No passwords,
PINs, backup codes, account enrollments, recovery contacts, or vault exports
were created or inspected. The local installed CLI's PIN-change help was
checked. UI wording, client compatibility, and migration behavior must be
verified against the versions used during execution.
