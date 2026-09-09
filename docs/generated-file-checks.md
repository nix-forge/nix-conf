# Checking generated scripts and configuration

Run `just generated-checks` from the repository root. It builds the
`generated-artifacts` flake check for the current platform with import from
derivation disabled. Each component also remains an individual flake check.
The aggregate collects generated-file checks and related Python helper tests;
the repository's formatting, type checks, package tests, and VM tests remain
separate checks.

Validate the final file that the application receives, including substituted
values, imported files, and the writer's interpreter line. A parser check on
the original `.in` file cannot establish that its rendered output is valid.
Checks attached to writers also run when their consumers build. Module fixtures
exercise serialization with quotes, spaces, backslashes, and ordered values.

| Files | Build validation and regression coverage |
| --- | --- |
| Bash templates | Bash parser and ShellCheck inspect the rendered body. Tests cover single-file, `bin`, and `libexec` outputs, shebangs, metadata, symlink invocation, shell options, and exact argument preservation including empty strings and newlines. Substitution-induced syntax and lint errors must fail. |
| Python commands | Nixpkgs' Python writer runs its checks. CRX tests extract real ZIP payloads from both supported headers and reject truncated, unsupported, oversized, and empty inputs without overwriting an existing output. Preference tests preserve unrelated settings and subsequent user choices. Existing browser, Dock, and VM host-resolution suites join the aggregate. |
| PowerShell | The native parser and pinned PSScriptAnalyzer 1.25.0 reject error and warning diagnostics. Syntax compatibility targets Windows PowerShell 5.1 by default. Tests require specific diagnostics for broken syntax, unused variables, empty catches, and incompatible syntax. The checker itself is analyzed against its PowerShell 7 runtime. |
| mpv Lua | The selected mpv Lua interpreter compiles the file without running it. Luacheck allows the injected `mp` API as read-only. Tests verify source preservation, reject syntax errors, unknown globals and API mutation, and exercise profile transitions through a recording mpv adapter. |
| Nushell | `nu-check --debug` parses the final Home Manager files and their imports without executing startup code. Tests cover environment escaping, PATH values, self references, invalid source, and invalid imported modules. |
| GTK CSS | GTK's CSS parser checks generated styles. Rejection tests include invalid values, missing files, and missing imports. Browser CSS has a different grammar and retains its own checks. |
| Caddyfile | `caddy adapt --validate` provisions the actual generated configuration with disposable fixture certificates. Tests inspect listeners, upstreams, and required client authentication, and reject missing certificate files. Validation does not start a server. |
| JSON, TOML, and application settings | Format generators serialize Nix values. Independent parsers check generated values and ordering. LinearMouse uses its pinned upstream schema, with schema mismatch and external-reference tests. Walker uses TOML generation and value regression checks; upstream has no published configuration schema. |
| XML and certificate extensions | Existing XML writers check well-formedness, and Libvirt definitions use its selected schemas. OpenSSL consumes the generated extension files; tests inspect client/server usage and subject alternative names. |

Linux runs the configuration fixtures that depend on Linux desktop packages.
Bash, Python helper, Lua, and Nushell checks are exposed on Darwin too. The
aggregate does not boot the separate service-command VM test or build the full
desktop closure. Follow the repository's desktop build placement instructions
for the latter; it validates the selected host's actual generated artifacts.

Keep rejection tests specific. A test that merely expects any nonzero exit can
pass because its checker crashed. Where the tool supplies stable diagnostics,
assert the relevant rule or error text as well as the failure status. Include
valid inputs and non-execution probes so a checker cannot pass by rejecting or
executing everything.

Update schemas with their applications and keep validators pinned. Document
rule exceptions next to the owning script or caller. The unattended Windows
provisioning helpers exclude `ShouldProcess` advice because partial `WhatIf`
support would misrepresent their behavior; the public Microsoft connectivity
probe has its own function-scoped exception. Generic PowerShell callers retain
the default rules.

These checks establish the tested syntax, contracts, and behavior. They do not
prove Windows cmdlet availability, live mpv playback, deployed certificate
validity, or native Darwin behavior from a Linux build. Walker-specific option
validation remains with the application until an upstream schema or suitable
configuration-checking command is available. Keep native integration tests for
those boundaries.

Validation on 2026-09-08 passed all 36 Linux aggregate components, the complete
desktop build on its native host, the package independence, policy and unit
checks, and package evaluation across all supported systems. The portable
aggregate evaluated for Apple Silicon Darwin. Changed Nix, Python, Lua, shell,
and documentation files passed their applicable format and static checks. No
system activation, native Darwin build, or live Windows guest test was performed.

The [generation and schema research](nix-generated-config-schema-research.md)
explains writer selection. Upstream documentation describes
[Caddy's provisioning validation](https://caddyserver.com/docs/command-line#caddy-validate)
and [PSScriptAnalyzer settings and diagnostics](https://learn.microsoft.com/en-us/powershell/module/psscriptanalyzer/invoke-scriptanalyzer?view=ps-modules).

## Organization-wide writer audit

The 2026-09-08 follow-up inspected all seven nix-forge repositories, including
hidden build files and templates without an `.in` suffix.

| Repository | Result |
| --- | --- |
| nix-conf | Bash templates already use the checked helper. Sourced setup fragments, UWSM data, CSS, Caddyfiles, sudoers, and Markdown retain their appropriate consumers and checks. |
| nix-seal | All three Bash substitution callers now use the local checked writer under `nix/lib`. It follows the same implementation and behavioral tests as nix-conf, while retaining an independent source tree. Activation tests verify dry runs and failure propagation. |
| vpn-confinement | The diagnostics command now passes a `replaceVarsWith` derivation directly to `writePython3Bin`. Strict substitution rejects missing placeholders before Python validation. A module fixture builds the installed command and runs its help interface. |
| nixpkgs-personal | The remaining inline hook scripts use `writeShellApplication`. Package asset and upstream source patches retain `substituteInPlace` inside their native package builds and installation checks. Package recipes remain independently copyable. |
| ci | Workflow tools already use `writeShellApplication` and `writePython3Bin`. There are no substitution-based executables requiring migration. |
| nix-config-framework | No substitution-based executable generation is present. Target discovery and composition remain its responsibility. |
| .github | Community metadata and workflow templates contain no Nix executable-generation sites. |

Apply script writers to complete programs. Sourced fragments depend on the
caller's shell and should not gain a wrapper or independent execution semantics.
Likewise, patches to an upstream application, SVG, or CSS file remain inputs to
that application's build or parser. A Bash writer would validate the wrong
language. Preserve native compiler, parser, schema, and package checks for these
cases.

The rollout passed nix-seal's full Linux flake check, including both runtime VM
tests, plus Rust formatting, Clippy, workspace tests, and its existing cargo-vet
policy. Its flake also evaluated across supported platforms. Package hooks
passed the package repository's pre-commit suite and a bytecode-cleanup test
with valid and invalid Python. All 72 VPN Linux check targets passed, including
12 runtime VMs; they ran in batches to avoid memory pressure from evaluating the
whole set together. The VPN diagnostics package also evaluated for ARM Linux.
These results cover the tested rollout snapshots; no activation or publication
was performed.
