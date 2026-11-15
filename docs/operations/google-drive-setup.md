# Google Drive desktop setup

The desktop profile mounts ordinary Google Drive files at `$HOME/Google Drive`
and adds a Files sidebar bookmark. The package and user service are declared in
[the desktop cloud module](../../homes/desktop/local/cloud/google-drive.nix).
Use the application-menu entry **Google Drive on the web** for native Docs,
Sheets, Slides and folder shortcuts. Those entries are deliberately hidden from
the filesystem mount to avoid misleading exports and shortcut deletion hazards.

## Create the Google client

1. Sign in to [Google Cloud Console](https://console.cloud.google.com/) with the
   account whose Drive should be connected. Create a project named
   **Personal Drive Desktop**. Its generated project ID can keep Google's default.
2. Open **APIs & Services**, then **Library**. Enable **Google Drive API**.
3. Open **Google Auth Platform**. Set the app name to **Personal Drive Desktop**,
   fill in the required support and developer-contact fields privately, and
   choose the **External** audience. Follow any required consent-screen fields.
4. Use **Production** publishing status for persistent authorization. Drive
   refresh tokens issued while the app is in Testing expire after seven days.
   Follow Google's personal-use verification guidance; this setup does not
   require distributing an application to other people.
5. Under **Clients**, create an OAuth client with application type **Desktop app**
   and name **NixOS Desktop**. Download its JSON file to private storage outside
   this repository. Set its permissions to 0600.

These steps follow [rclone's client instructions](https://rclone.org/drive/#making-your-own-client-id)
and [Google's OAuth documentation](https://developers.google.com/identity/protocols/oauth2).
Console labels can change. The required credential is a Desktop OAuth client
JSON file, not an API key, service-account key or mail application password.
Do not paste its contents or an authorization token into a chat or issue.

## Seal and deploy

The module declares two desktop-only secrets:

| Local name | Contents |
| --- | --- |
| `google-drive-config-password` | Random password for the writable rclone configuration |
| `google-drive-oauth-client` | Downloaded Desktop OAuth client JSON |

Their canonical sources live under `homes/desktop/local/secrets/`. Create them
through the [nix-seal bootstrap workflow](../../nix-seal/docs/nix-authoring.md#create-the-missing-values).
Use a cryptographically generated password rather than a Google account password.
Pass the JSON through protected stdin or a hidden multiline prompt. The JSON
contains private fields and must not appear in Nix strings, arguments or logs.
The encrypted `.age` file is the only repository input.

Export the integrated home's pending creation plan on the desktop:

```sh
workstation-task nix build --no-link --print-out-paths \
  '.#nixosConfigurations.desktop.config.home-manager.users.<USER>.nixSeal.bootstrapPlanFile'
```

Substitute the real home username before running. The returned plan is public.
If the authorizer key is on another machine, transfer this public plan there and
run `nix-seal secret bootstrap complete` against a private source workspace with
matching relative paths. Return only the resulting ciphertext to its canonical
path here. Keep administrator and authorizer private keys on their original
machine. Do not copy them to the desktop or into the repository.

Include new Nix sources and ciphertext deliberately in the Git source view, then
follow [secret preparation](../secrets.md#daily-operations) to sign and install the
target artifacts. Preparation is separate from activation. Build on the desktop
with `just os-build desktop`; activate with the established privileged route.
Read [desktop build placement](desktop-memory-management.md) before running
checks from another machine. A system switch can include other configuration
changes in the checkout, so inspect the intended generation before switching.

## Authorize in the desktop session

Once the signed secrets and home configuration have been activated, run this in
the desktop terminal:

```sh
google-drive setup
```

The helper reads the sealed client from nix-seal's protected runtime, encrypts
the initial rclone configuration before persisting it, and opens Google's
authorization flow. Sign in to the intended account and grant the Drive access
needed to manage existing files. A successful login starts the user service.
The configuration grants full Drive access; a mount folder is not an OAuth
permission boundary.

If browser authorization fails after the encrypted configuration was created,
resume it with:

```sh
google-drive reconnect
```

Setup refuses to overwrite an existing configuration. Reconnect preserves the
writable credential file and VFS cache. Status and manual controls are:

```sh
google-drive status
google-drive stop
google-drive start
```

The service starts with the graphical session after credentials exist. It skips
startup before authorization, rather than repeatedly failing during bootstrap.

## Storage and recovery

The writable encrypted token configuration and persistent VFS cache live under
`$XDG_STATE_HOME/google-drive`. Cache data is plaintext on encrypted local
storage. Keep the encryption password recoverable through nix-seal. Do not
delete or automatically clean this state directory while uploads are pending.
An application save can finish before Google receives the upload.

The initial cache target is 5 GiB with a 10 GiB minimum-free-space target. These
are eviction targets, not hard quotas. Open files and pending writes can require
more space. The read buffer is 8 MiB per open file and uploads use two concurrent
workers. The mount is restricted to the desktop user. It does not provide a
guaranteed offline replica, filesystem-wide transactional semantics or backup.
See [rclone's mount behavior](https://rclone.org/commands/rclone_mount/).

Deletions use Google Drive trash. Avoid concurrent edits to the same ordinary
file from several clients. Keep working repositories, databases, build outputs
and VM disks on local storage. Folder shortcuts and native Google documents
remain accessible through the browser.

## Verify the connection

Use a disposable test folder. Create a text file in Files, edit and rename it,
then confirm the contents through the browser. Make a browser-side change and
check that the desktop sees it. Delete the test file and confirm that Drive's
trash contains it. Test a network interruption with a disposable pending upload;
after connectivity returns, confirm it reaches Drive before clearing any cache.
Confirm the mount restarts after login and the cache survives reboot.

The helper reports operation errors without placing private filenames or OAuth
values in desktop notifications. A notification-daemon failure does not stop
the mount. Keep independent recovery copies of important files.
