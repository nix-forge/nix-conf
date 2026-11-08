# Research question

Reviewed: 2026-09-11. Scope: the `nix-seal prepare` configuration selector at
`nix-seal` revision `7f213a533ae7e626416de1e17c41f25bfc145674`, Nix
2.35.2 behavior, Nixpkgs revision
`c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0`, and Home Manager revision
`2c0350c759688177331b8f5242311fae8877bdb3`.

How should `nix-seal prepare` choose a normal deployment without asking the
user for a generated store path or making a host-dependent guess?

## Answer

Save one configuration selector in the flake's public `nixSeal` output and use
it when `prepare` receives neither `--flake` nor `--deployment`:

```nix
flake.nixSeal = {
  defaultConfiguration = "nixosConfigurations.desktop";
  # Existing public administrator catalogs remain here.
};
```

The ordinary command then becomes:

```console
nix-seal prepare --identity /path/to/admin.agekey \
  --signing-key /path/to/release.key
```

`prepare` should treat the current directory as the flake, read
`nixSeal.defaultConfiguration`, and build that configuration's
`config.nixSeal.deploymentFile`. `--flake <reference>` should do the same for a
different flake. `--flake <reference>#<configuration>` should remain the
explicit override. `--deployment <built-system-or-description>` should remain
the exact-built recovery input.

This follows Nix's useful convention: omitting an installable means the current
flake, and omitting its attribute selects a default chosen by the producer of
the command. The default belongs in the project because it describes which
configuration the project prepares. Private identity and signing-key paths are
different. They are machine-local inputs and should not enter this public
setting.

Do not infer the normal configuration from the executing machine's hostname or
user name. Those rules work for `nixos-rebuild` and Home Manager because each
tool has one configuration class and a well-defined local target. A single
`nix-seal` flake may contain NixOS, nix-darwin, and standalone Home Manager
configurations. Preparation may also run on an administrator machine for a
different target. A hostname rule would make the same checkout select different
deployments on different machines.

## Findings and sources

### Nix defaults are command-specific and project-visible

The Nix 2.35.2 manual says that most commands assume `.` when no installable is
given. It also says that a flake reference without an attribute uses a
command-specific default, usually `packages.<system>.default`. An explicit
attribute can resolve through the empty prefix, so a command can address a
tool-specific top-level output. See the versioned
[installable reference](https://nix.dev/manual/nix/2.35/command-ref/new-cli/nix#installables),
especially "Flake output attribute."

The relevant pattern is not the particular `packages` output. It is that the
command owns the meaning of omission while the flake publishes the chosen
default. For `nix-seal`, a public selector at
`nixSeal.defaultConfiguration` keeps the choice beside the configurations it
names. A selector string is preferable to a generated deployment path because
the latter changes with evaluation. It is also preferable to a direct recursive
reference to `deploymentFile`: the existing framework passes `flake.nixSeal`
into configuration module arguments, so storing the selector avoids a cycle
through `self.nixosConfigurations`.

The selector should be a configuration attribute path without a flake reference
or leading `#`, for example `nixosConfigurations.desktop`. Keeping the flake
location out of the value makes it portable when the checkout moves. The CLI
should validate the value as an attribute path before using it.

### NixOS and Home Manager guesses are narrower conventions

The current `nixos-rebuild-ng` parser turns an omitted flake fragment into
`nixosConfigurations.<hostname>`. It falls back to
`nixosConfigurations.default` only when it cannot obtain a hostname. With no
`--flake`, it also checks `/etc/nixos/flake.nix`. These rules are visible in the
immutable Nixpkgs
[flake parser source](https://github.com/NixOS/nixpkgs/blob/c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0/pkgs/by-name/ni/nixos-rebuild-ng/src/nixos_rebuild/models.py#L91-L151).

Home Manager uses a different rule. Without `--flake`, it first looks for a
flake under the user's XDG configuration directory. When a flake has no
fragment, it tries `USER@fqdn`, `USER@hostname`, `USER@short-hostname`, then
`USER` under `homeConfigurations`. See Home Manager's immutable
[`setFlakeAttribute` implementation](https://github.com/nix-community/home-manager/blob/2c0350c759688177331b8f5242311fae8877bdb3/home-manager/home-manager#L177-L223)
and its [standalone flake guide](https://nix-community.github.io/home-manager/nix-flakes/standalone.html).

These are precedents for concise commands, but not for a shared nix-seal guess.
Their selection functions are tied to one output type. They also depend on the
machine or account running the command, which may not be the nix-seal target.

### Project-local and user-local defaults solve different problems

Nix reads user-specific settings from its user configuration directory, and it
can take replacement configuration files from `NIX_USER_CONF_FILES`. See the
versioned [Nix configuration-file reference](https://nix.dev/manual/nix/2.35/command-ref/conf-file.html).
The Nix registry is also user-scoped by default. `nix registry add` maps a flake
identifier to a flake reference; it does not choose an output within that
flake. See the versioned
[`nix registry add` reference](https://nix.dev/manual/nix/2.30/command-ref/new-cli/nix3-registry-add).

A user-local nix-seal selector would be easy to make stale and would let two
operators prepare different configurations from the same checkout with the same
short command. A project setting is reviewable, follows the flake through clones,
and can be checked during evaluation. User-local configuration remains suitable
for private operational conveniences, but not for the deployment identity.

Candidate discovery should therefore improve errors without changing selection.
If `nixSeal.defaultConfiguration` is absent or invalid, inspect the public
`nixosConfigurations`, `darwinConfigurations`, and `homeConfigurations` names,
then print the persistent Nix setting and the explicit copyable `nix-seal
prepare --flake '.#<configuration>' ...` command for each candidate. Do not
silently choose the only candidate. Adding a second configuration would
otherwise change a formerly valid command into an ambiguity, and running the
checkout on a new host could change its meaning.

### Exact built deployments remain necessary for recovery

NixOS keeps exact system generations at paths such as
`/nix/var/nix/profiles/system-N-link`, and its rollback documentation invokes
the selected generation's own `switch-to-configuration`. See the official
[NixOS rollback procedure](https://nixos.org/manual/nixos/stable/#sec-rollback).
That is a different operation from evaluating the checkout's current default.

At the reviewed nix-seal revision, `--deployment` accepts either a deployment
description or a directory containing `nix-seal-deployment.json`. The NixOS
module places that file in every built system. See the immutable
[CLI resolver](https://github.com/nix-forge/nix-seal/blob/7f213a533ae7e626416de1e17c41f25bfc145674/crates/nix-seal-cli/src/preparation.rs#L232-L260)
and [NixOS system builder](https://github.com/nix-forge/nix-seal/blob/7f213a533ae7e626416de1e17c41f25bfc145674/nix/modules/nixos.nix#L343-L355).

Keep that input explicit. A readiness failure for a configuration marked as the
project default should recommend the stable `nix-seal prepare` command. A
failure from any other built configuration should print
`nix-seal prepare --deployment <exact-built-path> ...`. This distinction avoids
preparing today's default when the failed activation is a previous generation
or an explicitly selected non-default configuration.

The flake adapter can pass the saved selector into the selected module and mark
the generated readiness description when the current configuration matches it.
Standalone module use that lacks this provenance should take the safe recovery
branch and print the exact deployment input.

## Validation and limits

I inspected the installed Nixpkgs and Home Manager sources at the revisions
listed above and compared them with the immutable upstream files. I inspected
nix-seal's selector resolver, generated deployment description, and NixOS
system-builder link at its supplied base revision. Retrieval date for every web
source is 2026-09-11.

No implementation or runtime test was part of this research task. The Nix
manual still labels flakes and installables experimental. The recommended
`nixSeal.defaultConfiguration` name is a nix-seal convention inferred from the
primary-source patterns, not an existing Nix standard.

## Implication for this repository

The desktop flake should set:

```nix
flake.nixSeal.defaultConfiguration = "nixosConfigurations.desktop";
```

That configuration's existing `nixSeal.deploymentFile` already includes its
system target and embedded Home Manager targets, so the default must select the
configuration-wide description rather than reconstructing targets in the CLI.
