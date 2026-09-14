# Declarative package lookup

Reviewed: 2026-09-11. Scope: the pinned NixOS, Home Manager, nix-darwin,
and Determinate modules. The local cleanup used Determinate Nix 3.22.3,
based on Nix 2.35.2.

## Answer

Exclude imperative user profiles from the login environment. Keep the profiles
that expose declarative Home Manager and system packages. On Darwin, also keep
the global profile used by the external Nix installer.

This prevents imperative packages from shadowing declarative packages through
normal profile lookup. It does not prohibit `nix profile add`, `nix-env`, explicit
store paths, or manually modified environments. There is no documented
install-only prohibition in the reviewed [Nix settings reference](https://nix.dev/manual/nix/2.32/command-ref/conf-file.html).
Denying daemon access through `allowed-users` would also restrict ordinary Nix
workflows, so it is not an appropriate substitute.

## Findings and sources

NixOS derives executable, application-data, configuration, and other lookup paths
from `environment.profiles`. Its defaults include imperative user and global
profiles alongside declarative packages. Replacing that list with
`/etc/profiles/per-user/$USER` and `/run/current-system/sw` removes imperative
profile contributions to both `PATH` and XDG lookup.
See the pinned [shell environment](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/nixos/modules/config/shells-environment.nix),
[standard environment](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/nixos/modules/programs/environment.nix),
and [user module](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/nixos/modules/config/users-groups.nix).

With `home-manager.useUserPackages = true`, Home Manager installs packages through
`users.users.<name>.packages`, and its profile directory is
`/etc/profiles/per-user/<name>`. The policy preserves this directory, rather than
disabling Home Manager or its generations.
See the pinned [Home Manager integration](https://github.com/nix-community/home-manager/blob/2c0350c759688177331b8f5242311fae8877bdb3/nixos/common.nix).

Determinate's Darwin integration disables nix-darwin's Nix management with
`nix.enable = false`. Preserve `/nix/var/nix/profiles/default` for the externally
managed Nix installation. The Darwin policy excludes the user profile but retains
this global profile after the declarative paths.
See the pinned [Determinate module](https://github.com/DeterminateSystems/determinate/blob/cb76ac22754f6b36c008a3c39477c174a146dd6b/modules/nix-darwin/default.nix)
and [nix-darwin environment](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/environment/default.nix).

Modern profiles can be emptied with `nix profile remove --profile <PROFILE> --all`.
Identify the actual profile and inspect its manifest first. Do not target a
Home Manager profile, the system profile, or an installer-managed profile.
Removal creates a new profile version; keep previous versions for recovery with
`nix profile rollback`. Do not wipe history or collect the store as part of this
cleanup. Legacy `nix-env` profiles use a different manifest format and command.
See [profile removal](https://nix.dev/manual/nix/2.32/command-ref/new-cli/nix3-profile-remove)
and [profile versions and compatibility](https://nix.dev/manual/nix/2.32/command-ref/new-cli/nix3-profile).

The policy changes package discovery, not Nix execution permissions. Nix remains
available from the system on NixOS, preserving temporary use through `nix run`,
`nix shell`, and `nix develop`, as well as `nix build`. This is an inference from
the unchanged Nix executable and command behavior, not a security guarantee.
See [run](https://nix.dev/manual/nix/2.32/command-ref/new-cli/nix3-run)
and [develop](https://nix.dev/manual/nix/2.32/command-ref/new-cli/nix3-develop).

## Implementation and validation

[The shared Nix module](../modules/shared/nix-settings.nix) owns the system lookup
policy. Standalone Home Manager is unchanged because it can need its user profile
to install packages. [Platform contracts](../flake/dev/platform-checks.nix)
assert both operating-system profile lists and integrated Home Manager paths.

The platform-contracts check passed on x86_64 Linux, including evaluation of the
Darwin policy. A clean Bash subprocess sourced the generated NixOS login
environment and verified the exact executable path, the absence of imperative
profiles from PATH and XDG lookup, and access to the system Nix executable.
Formatting and whitespace checks passed. No Darwin runtime test or full system
activation was performed.

The local default imperative profile was emptied through the modern CLI after
checking its symlink and manifest. The previous profile version and Home Manager
generation were retained. Package commands then resolved through declarative user
or system packages.

Activate the configuration and start a fresh login session to apply the persistent
environment policy. Existing processes keep their environment. In particular,
the repository's [Nushell configuration](../modules/home/shells/nushell/extra-config-after.nix)
adds configured paths but retains inherited entries. Changing profiles does not
restart an already running application or force a launcher to forget cached entries.
