# nix-conf

NixOS and macOS workstation configuration with a guide to building your own.
Start with a small Home Manager environment, inspect what Nix generates, and
reuse the features that fit your setup.

[Read the guide](docs/README.md) · [Build the starter](docs/guide/first-configuration.md) · [Reuse a module](docs/guide/git.md)

## Start small

The [public starter](templates/starter/README.md) has its own pinned dependencies,
Git and shell settings, and a disposable NixOS practice VM. It needs no personal
credentials and does not activate anything on your account when you build it.
The complete workstations add desktop services, shared appearance, font selection,
and host-managed secrets.

| Goal | Entry point |
| --- | --- |
| Learn through a working example | [First configuration](docs/guide/first-configuration.md) |
| Boot a configured Linux system | [Console VM](docs/guide/virtual-machine.md) |
| Improve an existing configuration | [Git](docs/guide/git.md), [file search](docs/guide/file-search.md), [prompt](docs/guide/prompt.md) |
| Understand the desktop decisions | [Themes and fonts](docs/guide/appearance.md) |
| Find an independent package or framework | [Related projects](docs/guide/projects.md) |

The starter declares x86 Linux, ARM Linux, and Apple Silicon macOS. Its serial
VM is x86 Linux only. The [support table](docs/guide/support.md) distinguishes
evaluation, native builds, and runtime evidence. Personal host definitions are
hardware-specific integration examples, not installation templates.

## Appearance with evidence

Shared theme settings cover application colors and font roles. These recorded
Pango and Qt samples show multilingual text and emoji through two toolkits:

![Pango font test with digits, Latin, Arabic, Japanese, and emoji](docs/assets/font-implementation/pango.png)

![Qt font test with the same multilingual sample](docs/assets/font-implementation/qt.png)

These are reviewed font-test captures, not current desktop screenshots. See the
[appearance guide](docs/guide/appearance.md) for their context and the
[font reference](docs/font-configuration.md) for recorded checks.

If a guide step fails, use the [guide feedback form](https://github.com/nix-forge/nix-conf/issues/new?template=guide-feedback.yml).
A useful reproduction helps improve the next reader's experience. If this
project helps you, consider starring it so you can find it again.

## Repository map

| Location | Responsibility |
| --- | --- |
| [`flake.nix`](flake.nix) | Input pins, framework integration, supported systems, and public outputs |
| [`hosts/`](hosts/) | Operating-system targets, hardware, boot, and system policy |
| [`homes/`](homes/) | Home profiles, selected applications, and user preferences |
| [`modules/`](modules/) | Reusable NixOS, Darwin, Home Manager, and cross-platform features |
| [`overlays/`](overlays/README.md) | Package selection and registered temporary upstream fixes |
| [`lib/`](lib/default.nix) | Explicit shared helper exports, including checked script writers |
| [`flake/`](flake/) | Deployment, development tools, and check composition |
| [`tests/`](tests/) | Behavior tests, generated-output checks, and integration fixtures |
| [`docs/`](docs/) | Operational guides and reviewed technical evidence |
| [`pkgs/`](pkgs/README.md) | Separate repository for package recipes |
| [`nix-config-framework/`](nix-config-framework/README.md) | Separate repository for target discovery and module composition |
| [`nix-seal/`](nix-seal/README.md) | Separate repository for secret-management implementation |

The last three directories are Git submodules. Clone with `--recurse-submodules`,
or run `git submodule update --init --recursive` in a fresh checkout.
See [CONTRIBUTING.md](CONTRIBUTING.md) before changing configuration.

## How configuration is assembled

The framework discovers targets beneath `hosts/{nixos,darwin}/` and `homes/`.
Each target selects reusable features through the `modules` argument in its
`default.nix`. For example, `desktop-envs-hyprland` selects
[`modules/nixos/desktop-envs/hyprland.nix`](modules/nixos/desktop-envs/hyprland.nix).

The framework also imports Nix files beneath each target's `local/` directory.
These files must be modules; keep target-specific helper exports under the
module's `lib` option. Do not also list automatically imported files in the
target specification. Shared personal settings under `homes/shared/` and
`hosts/shared/` are imported explicitly by their consumers.

A reusable directory's `default.nix` controls its aggregate selection. Without
one, selecting the directory imports every Nix file below it. Adding a file to
such a directory can therefore change existing targets. Use an explicit
`default.nix` when a group needs a curated selection, and individual selectors
when targets need different features. See the
[selector contract](nix-config-framework/README.md#layout-and-selectors).

Hosts attach home profiles through `homes.<login>.config`. The framework owns
that integration and shares the host's package set with attached homes. Both
current home profiles require host-managed secret storage and set
`standalone = false`; build and activate them through their host.
See the [secret-management guide](docs/secrets.md).

Keep variations as typed options on the owning feature when behavior actually
varies. The browser suite and desktop modules already use this approach.
Use local settings for target policy, and keep reusable configuration beside
its implementation. The existing repository split lets package recipes and
the framework evolve without importing workstation policy.

## Working locally

Run `nix develop` for pinned development tools and `just --list` for commands.
Choose focused checks using the [validation guide](CONTRIBUTING.md#validation).
Evaluation, build, and activation establish different things; successful
evaluation alone does not validate a service at runtime.

Use `.` or an absolute checkout path as the flake reference. Nix then uses Git
source filtering, including tracked working-tree edits. Add intended new source
files with `git add -N <file>` or stage them before evaluation. An explicit
`path:` reference includes ignored local files too, so repository commands avoid
it. This distinction follows the
[Nix flake reference rules](https://nix.dev/manual/nix/2.35/command-ref/new-cli/nix3-flake.html#path-like-syntax).
Keep raw evidence and private material outside the checkout, as required by the
[publication policy](docs/publication.md).

Run full desktop system builds on the desktop host. On that host, use
`just os-build desktop` to build or `just os-switch desktop` to build and
activate; both use the workload runner. From another machine,
`just desktop-build` builds remotely and performs dry activation, while
`just desktop-deploy` activates the remote result. Darwin builds and runtime
checks require a suitable Darwin host. See [AGENTS.md](AGENTS.md) for build
placement.
