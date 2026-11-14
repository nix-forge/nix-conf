# Nix flake registry research and module design

## Decision

Use a small, declarative system registry for convenient CLI aliases. Map
each alias to the corresponding locked flake input with the module-level
`flake` option, keep `exact = true`, and disable the mutable remote global
registry on stock Nix installations. The registry is deliberately not an input
or dependency-management mechanism: flake inputs must remain explicit and
locked in `flake.lock`.

For Determinate Nix on nix-darwin, configure the equivalent entries through
`determinateNix.registry`, not `nix.registry`. Its module owns the generated
registry file and supported custom Nix configuration.

The recommended default aliases are only:

- `nixpkgs` → `inputs.nixpkgs`
- `self` → the configuration flake, when that CLI shortcut is useful

Additional aliases should be explicit opt-ins. Do not automatically export all
root flake inputs.

## What a registry does and does not do

Nix uses registries to rewrite convenient references such as
`nixpkgs#hello`. Registry precedence is global, then system, then user, then
`--override-flake`; therefore a user can override the system alias for that
user's own commands. This makes a registry a UX feature, not a security
boundary. [Nix registry reference](https://nix.dev/manual/nix/2.28/command-ref/new-cli/nix3-registry.html)

The same manual explicitly says that system and user registries are not
used to resolve references in `flake.nix`; they are used only on the command
line. A `flake.lock` is thus still the source of reproducibility and supply
chain review for configuration inputs. The global registry can participate in
flake input resolution, but relying on its mutable contents makes first-lock
resolution depend on remote state. [Nix registry reference](https://nix.dev/manual/nix/2.28/command-ref/new-cli/nix3-registry.html)

Registry matching is potentially broad unless `exact` is set: a `nixpkgs`
entry can otherwise match a reference such as `nixpkgs/nixos-20.09`. Upstream
NixOS, Home Manager, and Determinate's nix-darwin module all default `exact`
to `true`. Retain that default so an alias is exactly what it claims to be.
[Nix registry matching](https://nix.dev/manual/nix/2.28/command-ref/new-cli/nix3-registry.html), [NixOS module implementation](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/config/nix-flakes.nix), and [Determinate nix-darwin module implementation](https://github.com/DeterminateSystems/determinate/blob/b484316129e0089e28077f4ede85ac4dbd4b842f/modules/nix-darwin/default.nix#L483-L560).

## Performance and reproducibility

The upstream global registry is a downloaded URL. Nix caches it and refreshes
it when it is older than `tarball-ttl` (one hour by default); an empty
`flake-registry` setting disables it. A local system registry avoids this
network lookup and its mutable alias mapping for the aliases managed here.
[`flake-registry`](https://nix.dev/manual/nix/2.28/command-ref/conf-file.html#conf-flake-registry) and [`tarball-ttl`](https://nix.dev/manual/nix/2.28/command-ref/conf-file.html#conf-tarball-ttl).

Set an entry as `flake = inputs.nixpkgs`, rather than hand-writing a GitHub URL
or JSON. Upstream NixOS converts that value to a `path` target based on the
flake's store path and retains lock metadata when available. This gives CLI
commands the exact input used by the activated configuration; it avoids a
second fetch and makes `nix run nixpkgs#…`, `nix shell nixpkgs#…`, and
`nix search nixpkgs …` consistent with that generation. [NixOS registry module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/config/nix-flakes.nix).

This benefit has a closure-size cost. nix-darwin documents it for its default
`nixpkgs` registry pin: keeping the source in the system closure can be
undesirable if the machine will not run Nix commands. The same reasoning
applies to every input exported through a store-path registry entry. Therefore
registering every direct root input trades an occasionally useful shortcut for
larger system closures, more evaluation work, and a crowded `nix registry
list`. Keep the default allow-list small. [nix-darwin `setFlakeRegistry`](https://nix-darwin.github.io/nix-darwin/manual/#opt-nixpkgs.flake.setFlakeRegistry).

## Security posture

The registry should never be used as a trust or authorization boundary:

- A user registry has higher precedence than the system registry, and CLI
  `--override-flake` has higher precedence still.
- A registry mapping to a store path protects normal CLI use from a mutable
  registry URL, but it does not replace reviewing locked inputs, enforcing
  trusted binary-cache signatures, or normal Nix daemon authorization.
- Keep `exact = true` to prevent a bare alias from silently rewriting a
  branch/ref-qualified request.
- Do not configure `use-registries = false`: that disables the desired local
  registry along with the global one. Disable only the global source with
  `flake-registry = ""` on stock Nix. [Nix configuration reference](https://nix.dev/manual/nix/2.28/command-ref/conf-file.html#conf-use-registries).

## Platform-specific configuration

### NixOS and regular nix-darwin

`nix.registry` is the right interface. NixOS writes it to the system registry
at `/etc/nix/registry.json`; the Nix reference identifies that as the shared
registry location. [Nix registry reference](https://nix.dev/manual/nix/2.28/command-ref/new-cli/nix3-registry.html) Nix-darwin's own flake support uses
the same mechanism to pin `nixpkgs` to the source used to build the system.
[nix-darwin flake options](https://nix-darwin.github.io/nix-darwin/manual/#opt-nixpkgs.flake.setFlakeRegistry)

For those platforms, pair the local aliases with:

```nix
nix.settings.flake-registry = "";
```

This leaves the system and user registries enabled while removing only the
remote global registry. It is both faster and less surprising; unfamiliar
short aliases will fail clearly instead of resolving through an unreviewed
remote map. Full URLs such as `github:owner/repo` still work.

### Determinate Nix on nix-darwin

Determinate Nix owns `/etc/nix/nix.conf`; its supported custom configuration
location is `/etc/nix/nix.custom.conf`, exposed by its nix-darwin module as
`determinateNix.customSettings`. Do not attempt to manage the normal
`nix.registry` or `nix.settings` path when `determinateNix.enable = true`.
[Determinate Nix configuration](https://docs.determinate.systems/determinate-nix/) and [Determinate nix-darwin guide](https://docs.determinate.systems/guides/nix-darwin/).

Use:

```nix
determinateNix.registry = {
  nixpkgs.flake = inputs.nixpkgs;
  self.flake = self;
};
```

The Determinate module serializes this as a version-2 system registry at
`/etc/nix/registry.json`, then writes `flake-registry = /etc/nix/registry.json`
into its generated custom configuration. It also documents that the registry
is for CLI commands rather than flake references in Nix code. This local path
replaces Determinate Nix's default remote global registry, so do not add a
competing `flake-registry = ""` setting for this case. [Determinate module
source](https://github.com/DeterminateSystems/determinate/blob/b484316129e0089e28077f4ede85ac4dbd4b842f/modules/nix-darwin/default.nix#L734-L852)

Determinate's default global registry is remote and is refreshed according to
the usual `tarball-ttl`; its current `nixpkgs` mapping is a mutable FlakeHub
target. Replacing it with the local locked-input mapping produces the intended
deterministic CLI behavior. [Determinate `flake-registry` setting](https://manual.determinate.systems/command-ref/conf-file.html#conf-flake-registry) and [served Determinate registry](https://install.determinate.systems/flake-registry/stable/flake-registry.json).

### Home Manager

Home Manager's `nix.registry` writes a user-level registry under the XDG Nix
configuration directory. It is suitable only when no system-level module owns
the aliases (for example, standalone Home Manager). It is redundant—and can
shadow the system policy—when Home Manager is embedded in NixOS or nix-darwin.
[Home Manager `nix.registry`](https://nix-community.github.io/home-manager/options/home-manager/nix.html#opt-nix.registry)

For Determinate's Home Manager integration, `nix.package` is intentionally
`null` so Home Manager does not put an upstream Nix on `PATH`; leave the
registry to the system-level Determinate module. [Determinate Home Manager
module](https://github.com/DeterminateSystems/determinate/blob/b484316129e0089e28077f4ede85ac4dbd4b842f/modules/home-manager/default.nix).

## Module requirements for this repository

1. Replace lock-file parsing and automatic root-input enumeration with an
   explicit alias allow-list. The module should consume evaluated `inputs` and
   `self` only.
2. Generate one logical registry attribute set, with `nixpkgs` and optional
   `self` as the defaults. Make extra aliases a deliberate module argument or
   a clearly visible local list.
3. Route that same set to `nix.registry` for NixOS and non-Determinate Darwin,
   and to `determinateNix.registry` for Determinate Darwin.
4. Set `nix.settings.flake-registry = ""` only in the non-Determinate system
   branches. Do not set `use-registries = false`.
5. Avoid setting `NIX_PATH` as part of the registry module. Registry aliases
   do not change legacy `<nixpkgs>` lookups; adding that compatibility behavior
   should be a separate, explicit decision.
6. Keep Home Manager registry management only for standalone deployments and
   only when it actually manages a Nix client. Embedded Home Manager should
   inherit the system-level experience.

## Verification after implementation

Run these checks on each applicable host:

```sh
nix registry list
nix eval --raw nixpkgs#lib.version
nix run nixpkgs#hello
```

The list should show `nixpkgs` (and `self` if chosen) pointing to a local store
path, with no remote global entries. On Determinate Darwin, additionally
inspect `/etc/nix/registry.json` and `/etc/nix/nix.custom.conf`; the latter
should select that registry path. Test `nix registry add` separately if local
user overrides are an intended workflow, since it should remain possible and
is expected to take precedence.
