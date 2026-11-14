# Google Drive desktop integration

Reviewed: 2026-10-08. Scope: personal Google Drive file access on NixOS,
Hyprland and Nautilus. Upstream documentation retrieved on the review date.

## Answer

Use rclone to mount Google Drive as a folder, with full VFS caching, a systemd
user service and a Nautilus bookmark. This recommendation fits browsing,
editing, adding and deleting ordinary files without maintaining a complete
offline replica. Use the browser for native Google Docs, Sheets and Slides.
The recommendation follows documented capabilities and repository architecture;
it is not a measured performance comparison.

Google does not offer Drive for desktop on Linux. See
[Google's system requirements](https://support.google.com/drive/answer/2375082?hl=en).
The account includes 15 GB shared among Drive, mail and Photos; additional
capacity is available through Google One. See
[Google storage](https://support.google.com/drive/answer/9312312?hl=en).

## Findings and sources

### Versions and system fit

The root lockfile selects Nixpkgs revision
`c5c4a43b0e8056328ec4529f735cabdb8f1942bb`. Its
[rclone recipe](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/by-name/rc/rclone/package.nix)
contains version 1.75.0. Upstream lists 1.75.1, released 2026-09-04, including
security fixes for archive handling. Prefer the current patch release when
implementing, through a reviewed Nix package update rather than self-update.
See the [changelog](https://rclone.org/changelog/).

[The desktop home profile](../../homes/desktop/default.nix) selects Hyprland and
the desktop modules. [Desktop applications](../../modules/home/desktop/applications.nix)
select Nautilus. [Storage deployment](../../hosts/nixos/desktop/local/storage/deployment.nix)
enables the encrypted-root policy. These are configuration observations, not
proof of the currently active system. No additional desktop environment,
container or application server is necessary for this design.

### Filesystem behavior and resource use

Rclone mounts cloud storage through FUSE. Full VFS caching supports application
reads and writes through local disk storage. Uploads occur after files close and
the write-back delay elapses. Preserve the cache across restarts to resume
pending uploads. Cache limits are eviction targets; open files can exceed them.
RAM buffering scales with open files. Overlapping mounts must not share a cache.
See the [mount manual](https://rclone.org/commands/rclone_mount/).

Proposed starting values, to be measured after implementation:

| Setting | Starting choice | Purpose |
| --- | --- | --- |
| Cache mode | `full` | Support ordinary desktop file access |
| Read buffer | `8Mi` | Keep per-file buffering conservative |
| Disk cache target | `5Gi` | Reuse recently accessed data |
| Minimum free space target | `10Gi` | Leave local disk headroom |
| Concurrent uploads | `2` | Start with modest network and memory demand |
| Directory polling | Upstream default | Avoid speculative tuning |
| Permissions | Owner only, `--umask 077` | Restrict other local users |

Adjust cache capacity to disk space and the largest files being edited. Verify
that cache data survives logout and reboot, and that cleanup tools preserve
pending uploads. Do not treat cached content as guaranteed offline availability.
Avoid indexing or backup traversal of the mount; these can cause unnecessary
downloads. Disable bulk remote thumbnails if they cause traffic. Keep Git
working trees, databases, build outputs and VM images on local storage.

### Authentication and deletion

Use a dedicated Google OAuth Desktop app client with the Drive API enabled.
Current rclone instructions warn that the shared client is being retired.
Browsing and modifying existing files requires the full Drive scope;
`drive.file` restricts access to files created by rclone. A mount restricted to
a folder does not narrow the OAuth grant. Preserve the default Drive-trash
behavior. Review folder shortcuts before exposing them: deleting a shortcut
through the mount can affect its target contents. Native Google document
exports do not provide live collaborative editing. See the
[Drive backend](https://rclone.org/drive/).

External OAuth apps left in Testing receive refresh tokens that expire after
seven days for Drive access. Configure the consent screen for Production and
follow the personal-use instructions, including any console requirements.
Production status does not imply releasing a public application. See
[Google OAuth token expiration](https://developers.google.com/identity/protocols/oauth2)
and [rclone's client setup](https://rclone.org/drive/#making-your-own-client-id).

Keep OAuth configuration private, writable and outside Git and the Nix store;
rclone must persist refreshed tokens. Use directory mode 0700 and file mode
0600, with encrypted configuration where practical. An unattended service needs
a secure runtime method to obtain its unlock secret. Follow
[repository secret management](../secrets.md); do not substitute an immutable
plaintext Nix-generated configuration for writable credential state. Rclone's
password obfuscation is reversible and is not configuration encryption. See
[configuration encryption](https://rclone.org/docs/#configuration-encryption).
Protect the Google account with a
[passkey](https://support.google.com/accounts/answer/13548313?hl=en).

For confidential files, an optional separate
[rclone crypt remote](https://rclone.org/crypt/) encrypts content and names before
upload. Retain its password and optional salt for recovery. File sizes and
modification times remain exposed, and the unlocked local view is plaintext.
Encrypted files lose normal Google preview and native editing workflows.
[Cryptomator](https://docs.cryptomator.org/security/security-target/) is an
alternative when a separate vault interface is preferred.

### Alternatives

| Option | Appropriate use | Assessment for this desktop |
| --- | --- | --- |
| Rclone mount | On-demand folder access | Recommended for the requested behavior |
| Insync | Paid GUI with selective offline synchronization | Consider if guaranteed offline copies become necessary |
| google-drive-ocamlfuse | Dedicated Linux Drive mount | Active alternative; no comparative benchmark establishes an advantage here |
| Rclone bisync | Managed two-way replicas | Adds state, conflict and deletion handling that this request does not require |

[Insync's Linux page](https://www.insynchq.com/linux) distinguishes its major
supported distributions from other distributions users run, including NixOS.
Do not assume equal vendor support or lower resource use on NixOS.
[google-drive-ocamlfuse](https://github.com/astrada/google-drive-ocamlfuse)
provides mounting and read-only native document exports.
[Bisync documentation](https://rclone.org/bisync/) warns about data loss from
incorrect use and documents its state and recovery requirements.

Older GNOME Online Accounts tutorials are a poor starting point. A GNOME
maintainer describes the Google GVfs backend dependency and migration problems
and its removal from the visible account setup in March 2026. See the
[maintainer explanation](https://discourse.gnome.org/t/google-drive-in-gnome-50/34417/7).

## Validation and limits

Inspected selected repository modules, the lockfile, the pinned upstream package
recipe and primary documentation. No package installation, account login,
evaluation, build or runtime benchmark ran. No claims of measured CPU, RAM,
latency or application compatibility follow from this research.

Before relying on the integration, test a disposable folder for creation,
editing, renaming, deletion to Drive trash, browser-originated changes and
upload recovery after a network interruption and reboot. Confirm real files
arrive in the browser before clearing cache or treating a save as uploaded.
Concurrent editing from several clients needs a separate conflict test.

## Implication for this repository

The [desktop integration](../../homes/desktop/local/cloud/google-drive.nix) now
implements this design, with a private encrypted token configuration and two
separate nix-seal credentials. See the [setup guide](../operations/google-drive-setup.md).
Ten helper behavior tests passed on macOS; isolated Home Manager and nix-seal
evaluation of the module produced no failed assertions. Python lint, formatting,
type checks, Markdown checks and a focused secret scan passed. This evidence
does not establish a desktop system build, activation or authenticated Drive
file access. Those steps remain pending.

Install the package through Home Manager and own the user service beside its
feature module. Keep desktop-specific selection under the desktop profile.
Add a Nautilus bookmark using the existing
[file-manager conventions](file-manager-research.md). Configure explicit paths
for writable credentials, persistent cache and the empty mount directory;
arrange the NixOS FUSE helper and service restart behavior without granting
other users access. Provide visible upload-failure reporting before calling the
setup complete. Mount access is not a backup; retain independent recovery copies
of important files.
