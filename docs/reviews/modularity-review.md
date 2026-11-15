# Reusable configuration and module independence

Reviewed on 2026-10-13 against the current working files, including staged and
unstaged changes. The root baseline was
`84e37f5d83e1b218ce8c2c843fe3f9ead479b12c`. Existing work was preserved.

## Scope and boundaries

The audit searched all root home, shared, NixOS and Darwin module sources for
personal identities, network addresses, credential catalogs, machine paths and
undeclared option dependencies. Independent read-only reviews covered home and
shared modules, system modules and targets, and the four submodule boundaries.
The submodule review used targeted searches and inspected affected composition
and service paths. It was not a line-by-line review of every package or Rust
implementation.

Personal configuration belongs under `hosts/**/local/` or `homes/**/local/`.
Target entry points retain the discovery metadata needed to identify systems,
users and attached homes, and select reusable features. Public source locations,
maintainer attribution, fixture identities, protocol constants and configurable
opinionated defaults are not personal runtime configuration.

## Implemented corrections

- Shared personal browser, signing, secret and network policy moved under the
  corresponding shared `local/` trees. Target-specific secret modules and disk
  layouts moved under their targets' local trees. Inline home preferences and
  platform settings became automatically imported local modules.
- Concrete deployment outputs, installer composition, trust anchors, build
  placement policy and host-specific recipes moved into local configuration.
  The evidence and remote realization commands consume caller-supplied placement
  policy. Existing command names remain available through the root justfile.
- Feishin has an optional managed-login interface using runtime credential files.
  Importing the reusable feature does not declare a personal secret catalog or
  SSH tunnel. Its required mpv player and Darwin application copying receive
  composable defaults. Existing server login and tunnel policy are local.
- Desktop core imports its component declarations. Idle and Noctalia tolerate
  missing sibling modules. Noctalia disables overlapping components only when
  their options exist, validates clock times, and preserves the optional lock
  integration. Hyprsunset asserts its compositor requirement.
- HDR selects the preferred monitor mode by default and accepts caller-declared
  unsupported outputs. Personal monitor and capture-output choices remain local.
- Browser native-messaging paths respect `xdg.configHome`. Actual supplies a
  Documents-directory fallback when XDG user directories are disabled. Darwin
  screenshot defaults derive the configured account home.
- Actual CLI is a maintained, independently discoverable package using the
  upstream Actual source and dependency cache. Its obsolete credential-file
  backport was removed because the selected upstream release provides that
  interface. Feishin supports executable-only custom mpv packages on macOS by
  constructing its private application bundle when the package supplies none.
- Stylix integration tolerates absent greeter and typography modules. Theme and
  palette declarations are separate from application targets, so individual
  targets import their intrinsic theme module without a sibling bundle.
  Independently selectable NixOS theme components import their declaration owner. Public option
  documentation evaluates portable modules separately from personal hosts.
- Bluetooth pairing and audio policy follow effective service enablement.
  DNS modules supply their intrinsic resolver dependencies. DNS bootstrap provider
  choice is explicit and local. Unbound restricts its listener to unprivileged
  ports and requires authenticated forwarder syntax. NetworkManager uses native
  DNS integration alone and respects a selected filtering or validating resolver.
- Libvirt and the tarpit assert the enabled nftables firewall that owns their
  isolation rules. The tarpit rejects global port and port-range openings.
- Boot blessing uses the configured ESP mount. Secure Boot validates persistent
  signing-key paths and no longer assumes a particular MAC policy or runtime
  driver-loading strategy. Desktop-specific restrictions remain local.
- Windows guest network assertions handle missing network names. UTC is the
  portable timezone default; the existing timezone choice remains local.
  Libvirt XML metadata uses project namespaces rather than a personal domain.
- The obsolete Minecraft recipe referenced an absent flake input and exposed a
  helper as a module selector. The feature now uses the native NixOS Minecraft
  server interface, including upstream EULA validation and package/JVM options.
- Codex desktop integration imports its settings declaration, respects XDG data
  directories and exports the required system classes for runtime configuration.
- Attached Home Manager profiles receive their own framework target identifiers.
  Secret integration reads optional per-home module arguments and retains the
  enclosing host's deployment selector for embedded readiness checks. An owning
  assertion rejects home/host architecture mismatches.

## Library and source organization

The exported template writers, syntax checkers, process helper and Hyprland
package resolver have multiple consumers. Directory collection is a general
recursive algorithm; its function signature documentation was corrected.
Single-caller build orchestration moved from `lib/` into `scripts/`.
Target-specific disk constructors are exported through local module `lib`
options, with explicit offline installer entry points. They are not accidentally
imported as unconditional disk layouts.

The review used the module system's own options, defaults and assertions rather
than adding tests that read back personal host settings. Upstream guidance
supports assertions for invalid combinations and states that Home Manager module
arguments and imports follow the NixOS module system. See the
[NixOS module manual](https://nixos.org/manual/nixos/unstable/#sec-writing-modules).
The actual pinned framework and module sources determine the implementation.

## Further corrections

A second pass broadened the standalone-module review and built the Linux Python
suite to exercise behavior skipped on macOS.

- The kernel baseline uses Nixpkgs' portable kernel default. The desktop retains
  its explicit XanMod selection locally. Disabled TRIM removes both maintenance
  units, and callers can override its command normally.
- Missing wordlist sources produce the owning compatibility assertion instead
  of failing while looking up an absent attribute.
- Fzf retains history search without Atuin. Atuin uses Home Manager's native
  integrations, including package selection and disable switches. The obsolete
  Nushell shim was retired; older package overrides receive a compatibility
  assertion when Nushell integration is selected. The fix is documented in
  [Atuin 18.20.1's release notes](https://github.com/atuinsh/atuin/releases/tag/v18.20.1).
- Ghostty accepts an externally managed package when its native systemd
  integration is disabled. Default editor, visual editor and terminal selectors
  import their executable providers. Stable module keys prevent duplicate option
  declarations when consumers also select those providers directly.
  Neovim's theme repair belongs to the theme profile, allowing the editor to
  evaluate without importing theme helpers.
- Blueman applet suppression is configurable and follows the effective desktop
  indicator selection instead of assuming a companion bar is present.
- Clipboard history owns a logind lock listener. It subscribes before reading
  session state, verifies the service's bus owner and the session's user, and
  handles owner changes through service-manager restarts. IPC and cleanup have
  deadlines; a child ignoring termination is killed and reaped. Idle integration
  can still perform immediate cleanup on compositor lock notifications.
- Public tmux settings are defaults, and generated arguments use tmux's own
  quoting rules. A real isolated server verifies overrides and literal strings,
  following the [tmux command syntax](https://man.openbsd.org/tmux.1#COMMAND_PARSING).
- Remote build preparation supports callers without Linux cgroups. Fixture
  commands resolve tools from their test environment. The sandbox includes the
  backup wrapper it exercises, and process fixtures publish complete PID markers
  atomically before notifying readers.

## Validation

`module-independence` exercises standalone and composed features with generic
fixture accounts, paths and network data. It checks missing sibling modules,
credential paths, disabled services, resolver ownership, authenticated forwarding,
firewall requirements, portable defaults and native Minecraft selection.
Framework discovery uses different host and home target names. Secret module
fixtures exercise optional module arguments and embedded deployment selectors.
Homelab dashboard fixtures check native listener changes and explicit overrides,
including IPv6 loopback proxying and malformed IPv6 rejection.
Existing command and installer tests cover relocated operational sources.

Passing validation:

- Desktop NixOS, Raspberry Pi NixOS and macOS system derivation evaluation.
- Linux `module-independence` evaluation on x86_64 and a built check on aarch64,
  including custom and disabled mpv packages.
- Framework discovery, secret target derivation, theme target contracts and
  homelab operations contract evaluation. Homelab's standalone check used the
  current workspace package input because its published package pin does not
  contain an existing unpublished dependency.
- A built portable option-reference JSON and built Actual CLI plus version test
  on aarch64 Linux.
- Package repository `check-flake.sh` completed check-derivation and flake-output
  evaluation for aarch64 Darwin, aarch64 Linux and x86_64 Linux. This recipe does
  not build the complete package matrix. Swift hardening and Finder helper checks
  also evaluate directly from reusable overlays without a personal system target.
- Focused operational, installer and evidence tests: 162 passed, one deselected.
  Credential importer and macOS player-bundle tests: 39 passed, with 24 passing
  subtests. Player fixtures cover both package shapes; signing is stubbed.
- Formatting, focused Python and shell lint, unused Nix binding checks,
  whitespace checks, moved-source reference review, just recipe discovery and
  secret/publication scanning of the new review and package documentation.
- The broader macOS Python run passed 644 tests and 44 subtests, with 65
  platform-specific skips and 53 deselections. The expanded Linux sandbox suite
  passed 713 tests with 53 deselections after its portability and readiness fixes.
  The updated module-independence check built on aarch64 Linux. The native macOS
  tmux configuration check built, and focused Python type checks passed.

Evaluation alone does not establish complete system builds, activation, firmware
enrollment, hardware behavior or native application behavior. The desktop's
workload queue was occupied by unrelated work, so validation used a private source
snapshot on another host for evaluation and isolated checks. No configurations
were activated. The review does not claim every package or implementation was
audited line by line.
