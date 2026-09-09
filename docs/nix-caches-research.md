# Where to configure Nix binary caches

Reviewed: 2026-09-08. Scope: this repository's NixOS, nix-darwin, and Home
Manager configuration; installed Determinate Nix 3.22.2, based on Nix 2.35.2.
Upstream documentation and source links were retrieved on the review date.

## Answer

Keep a small `nixConfig` cache list in [the root flake](../flake.nix) for the
first build. Select persistent caches through
[the shared cache module](../modules/shared/cache.nix), using the enabled
features of each system or home configuration. These settings serve different
stages of a rebuild, so some deliberate duplication is useful.

A newly enabled module generates the next configuration. Its cache settings
become persistent when that configuration is activated, after its packages have
already been built. The current build needs an existing cache setting, an
accepted flake setting, or an explicit command-line setting. This ordering
follows the NixOS rebuild process, which builds the system before activating it.
See the [NixOS manual](https://nixos.org/manual/nixos/stable/#sec-changing-config).

The flake list applies when evaluating any output of this repository. It cannot
follow an individual target's feature selection. This is the chosen tradeoff
for first-build convenience. Ordinary builds outside this flake use the
activated system or user settings.

## Findings and sources

### Flake configuration and daemon configuration

Nix describes `nixConfig` as command configuration applied when evaluating a
flake. Cache settings need confirmation unless `accept-flake-config` is enabled.
Use `--accept-flake-config` for a reviewed invocation instead of enabling it
globally. See the [flake reference](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-flake.html#flake-format).

The [flake loader](https://github.com/NixOS/nix/blob/2.34.1/src/libflake/flake.cc#L299)
expects a literal configuration set and literal setting values. A local
experiment confirmed that `nixConfig = import ./cache.nix` and a `let`
expression fail with `expected a set but got a thunk`. A literal set succeeds.
The same loader applies the root flake's configuration before traversing its
inputs. It does not merge the `nixConfig` of dependency flakes. Consequently,
adding a package flake as an input does not automatically enable its cache.

`substituters` selects cache URLs. `trusted-public-keys` authenticates signed
store objects. `trusted-substituters` permits unprivileged clients to request
additional URLs, but does not enable those URLs by itself. A flake's accepted
settings do not make an unprivileged client a trusted daemon user. These are
separate controls in the [Nix configuration reference](https://nix.dev/manual/nix/2.34/command-ref/conf-file.html).

The [daemon implementation](https://github.com/NixOS/nix/blob/2.34.1/src/libstore/daemon.cc)
also permits an unprivileged client to select URLs already present in the
daemon's `substituters`. Repeating every active URL in `trusted-substituters`
is unnecessary. The daemon ignores a new signing key supplied by an
untrusted client. Home Manager can write client configuration, but cannot
authorize a new key for a separately managed system daemon.

For a first build on a machine whose daemon does not yet trust these providers,
run the reviewed build with administrator privileges or first have the
administrator configure its cache URLs and keys. For example, on the target
NixOS machine:

```sh
sudo nix build --accept-flake-config \
  '.#nixosConfigurations.<HOSTNAME>.config.system.build.toplevel'
```

Replace the placeholder with the configured target. Follow
[the desktop build-placement rule](../AGENTS.md) for the desktop closure.
This command builds a result; activation remains a separate action. Existing
trusted daemon users can also supply the settings without `sudo`.

### Cache selection is configuration policy

A derivation does not carry daemon cache permissions. Enabling a cache beside
a package means that its configuration module contributes cache policy when
selected. The cache can then supply any matching trusted store object used by
that Nix invocation. This is an inference from the separate derivation and
daemon settings interfaces, not a package-level restriction on cache authority.

Keep the public NixOS cache as the base provider. Add the existing
[Nix Community cache](https://nix-community.org/cache/) as the common supplemental
provider. Its key also appears in the pinned
[Stylix flake](https://github.com/nix-community/stylix/blob/5e3809851f486e7fc7e84b40f174c74b60ecc784/flake.nix).

| Provider | Persistent selection | Evidence and expected benefit |
| --- | --- | --- |
| Nix Community | Shared cache baseline | Existing provider for community projects. |
| Hyprland | Hyprland or Hyprlock enabled | [Hyprland's cache documentation](https://wiki.hypr.land/Nix/Cachix/) publishes its URL and key for packages from its flake. |
| NixOS CUDA | Linux package set enables `cudaSupport`, or an explicit cache override | The [CUDA documentation](https://wiki.nixos.org/wiki/CUDA#Setting_up_CUDA_Binary_Cache) publishes `https://cache.nixos-cuda.org` and its current key. This is the missing provider for CUDA-enabled builds. |
| Noctalia | Noctalia enabled | [Noctalia's installation documentation](https://docs.noctalia.dev/noctalia/getting-started/nixos/) publishes its URL, key, and cached branch. Preserve the existing provider with feature-based selection. |

The current CUDA endpoint is `cache.nixos-cuda.org`, with key
`cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=`.
Use that documented endpoint rather than the older
`cuda-maintainers.cachix.org`. The project's
[maintainer site](https://nixos-cuda.org/) identifies its current Hydra
infrastructure. Enabling CUDA for an individual package may need an explicit
`nix.caches.cuda.enable = true` because the package set's global `cudaSupport`
flag will remain false.

Determinate Nix owns the base daemon configuration on Darwin. Its pinned
[nix-darwin module](https://github.com/DeterminateSystems/determinate/blob/cb76ac22754f6b36c008a3c39477c174a146dd6b/modules/nix-darwin/default.nix)
writes `determinateNix.customSettings` to the custom configuration file. Keep
the repository's `extra-substituters` and `extra-trusted-public-keys` approach
there so its managed base settings survive. Nix's `extra-` prefix appends to
list settings instead of replacing them.

### A configured cache does not guarantee a hit

Hyprland and Noctalia both warn that overriding their `nixpkgs` inputs changes
the build and can invalidate their cached results. This repository uses
`follows` and additionally patches
[Hyprland and its portal](../modules/nixos/desktop-envs/hyprland.nix). Its
[Noctalia package](../pkgs/pkgs/by-name/no/noctalia-personal/package.nix) also
changes the upstream build. Those final packages should still need local
builds; matching dependencies may come from the caches. Cache configuration
alone is not a reason to remove required patches or change the input graph.

Other reviewed candidates do not justify more trusted providers in this change:

- NVF publishes its cache in the pinned
  [cache workflow](https://github.com/NotAShelf/nvf/blob/5e4f212f8720c17fdd06f5c57591f251aff67453/.github/workflows/cachix.yml).
  It builds example configurations on an Ubuntu runner. The repository uses a
  customized editor on Linux and Darwin, so final-package coverage was not
  established. Follow-up metadata requests found the sampled Neovim, LuaJIT,
  and Tree-sitter outputs already in the official NixOS cache.
- Spicetify's pinned
  [update workflow](https://github.com/Gerg-L/spicetify-nix/blob/27ff19b00338052e8a504e1d1a34efad82c4bb26/.github/workflows/update_deps.yaml)
  caches its updater and a small test configuration. Coverage for the
  repository's customized Spotify build was not established. The selected
  Spicetify CLI output already has metadata in the official NixOS cache.
- [Flox's public CUDA cache](https://flox.dev/cuda/) supports ordinary Nix
  clients. Its [announcement](https://flox.dev/blog/the-flox-catalog-now-contains-nvidia-cuda/)
  publishes the URL and signing key. Metadata for the pinned CUDA runtime,
  NVRTC, cuDNN, cuBLAS, and sampled FFmpeg output was available from both Flox
  and the selected NixOS CUDA cache. The four CUDA library outputs were absent
  from the official NixOS cache. This establishes useful CUDA-cache coverage,
  but no additional coverage from Flox in this sample. Keep Flox as a candidate
  if missing outputs or provider reliability become a problem.
- Zen's pinned
  [quality workflow](https://github.com/0xc000022070/zen-browser-flake/blob/fdb83f8fce835213fab7eab52c375926fe1a32dc/.github/workflows/code-quality.yml)
  uses a `deadnix` cache for linting. That does not establish a browser cache.
  Reviewing the locked Helium flakes and nix4vscode entry points, READMEs, and
  workflows found no additional advertised package cache.

## Validation and limits

The isolated flake syntax experiments ran on Linux with Determinate Nix
3.22.2. They evaluated metadata only and changed no daemon settings. Reviewed
input revisions are recorded by [flake.lock](../flake.lock); immutable links
above identify the upstream source inspected.

An HTTP request to the CUDA endpoint's `nix-cache-info` succeeded and reported
priority 50. Direct Cachix metadata requests returned HTTP 403 in this research
environment; one API hostname timed out. These results do not establish a
provider outage or a successful package substitution. No closure was downloaded
to measure hit rates, and no system activation or Darwin runtime test ran as
part of this research.

Implementation validation on Linux passed the `cache-policy` check and
`nix flake check --no-build`. The cache check covers feature selection,
explicit overrides, removing Noctalia from an integrated home, standalone Home
Manager, ordinary nix-darwin, and the configured Determinate Darwin host.
It also checks that the flake's bootstrap URLs and keys match the complete
provider catalog, independently of any host's feature selection.
The generated NixOS `nix.conf` artifact built successfully.
The public NixOS cache and signature verification remain enabled.

The repository formatter and Gitleaks passed for the changed files. These
checks verify evaluation and generated configuration, not cache hit rates or
activation. The full flake check omitted incompatible Linux ARM and Darwin
checks; the cache-specific Darwin evaluations ran as part of `cache-policy`.

## Implication for this repository

Use `nix.caches.<provider>.enable` as the explicit override, with defaults based
on the selected configuration. Integrated Home Manager features must contribute
to the host's daemon cache selection; standalone Home Manager contributes
client settings subject to the daemon's existing trust policy. Keep the root
flake's small bootstrap union synchronized with the provider definitions through
an evaluation check. This preserves first-build support and gives persistent
cache settings a single configuration owner.

An integrated home that selects the shared cache module can request a cache
for a package override in its own configuration:

```nix
nix.caches.cuda.enable = true;
```

When the host also selects the cache module, that request contributes to its
daemon settings. An explicit host setting takes precedence over requests from
its homes. An integrated home then emits no duplicate client cache settings.
Homes on hosts without the cache module retain client settings, subject to
the existing daemon trust policy. The regression check reproduces a home
request being ignored before this change and verifies it reaches the daemon
afterward. It also checks that an explicit host opt-out wins.

These overrides control persistent configuration. The accepted root flake
list still applies to commands using this flake, including when a host opts
out of one of its providers. That is the deliberate bootstrap tradeoff above.
Previously saved flake-setting approvals also remain effective when
`accept-flake-config` is false, as shown by Nix's
[configuration loader](https://github.com/NixOS/nix/blob/2.34.1/src/libflake/config.cc).
Removing a provider completely requires reviewing the bootstrap hints too.
