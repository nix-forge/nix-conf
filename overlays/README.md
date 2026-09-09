# Overrides and overlays

Temporary package and upstream module fixes live in [`temporary/`](temporary/default.nix).
Long-lived package selection and behavior live in [`permanent/`](permanent/).
[`default.nix`](default.nix) is a Nixpkgs overlay. Each target installs it through
`nixpkgsArgs.overlays`; attached Home Manager configurations share their host's
package set through `useGlobalPkgs`.
[`packages.nix`](packages.nix) owns platform conditions, package sources, and
the order in which fixes apply. It receives the incoming `prev` package set.

Modules use ordinary package attributes:

```nix
{ pkgs, ... }: {
  home.packages = [ pkgs.prismlauncher ];
}
```

Retire each package fix in `packages.nix`. When an attribute needs no remaining fixes or
customizations, remove its override. The same module reference then resolves to
the upstream Nixpkgs package.
No custom module argument or package-selection helper is needed.

The overlay applies the selected package definitions throughout the configured
package set. The GtkSourceView repair remains confined to Virt Manager's dependency;
`pkgs.gtksourceview4` itself keeps its upstream definition. `pkgs.grimblast-region`
is a separate permanent variant, while `pkgs.grimblast` retains its normal behavior.

The overlay also owns the Determinate Nix package selection, its Darwin test
condition, the Darwin Actual repair, and the Linux Zen wrapper repair. The
Determinate modules configure the service and daemon settings.

## Which repository owns an override?

| Change | Location |
| --- | --- |
| Workaround for a broken upstream package used by this configuration | `overlays/temporary/<name>.nix` and `overlays/temporary/patches/` |
| Repair to an upstream NixOS, Home Manager, or flake module | `overlays/temporary/<name>.nix`, registered in `temporary/default.nix` |
| Lasting package selection or behavior shared by this configuration | `overlays/permanent/` |
| Independently useful package recipe or named variant | `pkgs/`, the separate nixpkgs-personal repository |
| Module settings, wrapper flags derived from options, feature selection | The owning module |

Classify a change by what it repairs. Rewriting upstream Nix source, replacing
an upstream module with `disabledModules`, or adapting option assignments inside
an upstream module is a temporary upstream fix even when implemented as a Nix module. Keep the
repair and its lifecycle record in `temporary/`; the owning configuration module
only selects the registered fix. Ordinary option values remain in their owning
module.

An `overrideAttrs` expression can be a package recipe. Its syntax does not decide
where it belongs. For example, `twemoji-color-font-optional` removes default
Fontconfig substitutions, `mplus-outline-fonts-compatible` avoids duplicate font
files, and `noctalia-personal` supplies selected UI behavior. Those reusable
variants belong in nixpkgs-personal. Keep repairs needed to build such a variant
with its recipe and validate them in that repository. Do not introduce a
dependency from nixpkgs-personal back into this configuration.

The permanent Determinate overlay selects the Nix implementation. Its Darwin
test workaround is a separate temporary fix. Region-only Grimblast behavior is
a permanent override. Module-specific Git options and browser flags stay with
the module that owns those options.

Use `prev` for the incoming package in an overlay. Preserve the existing scope
when moving a local override. The GtkSourceView fix here still applies only to
Virt Manager's dependency. See the [Nixpkgs overlay and override documentation](https://nixos.org/manual/nixpkgs/unstable/index.html#chap-overlays).

Module fixes use the same registry and revision guard as package fixes. Their
`apply` function takes the upstream input and returns a module. The owning module
imports that result, as the Neovim module does for `stylix-nvf`. Construct its
registry with `{ inherit inputs lib; }` so import resolution does not depend on
`config._module.args.pkgs`. Module fixes stay outside the Nixpkgs overlay in `packages.nix`; they need no package version range.

## Temporary fix lifecycle

Every registered fix records its reason, upstream link, removal condition, input
path, and an explicitly reviewed input revision. Do not derive
`reviewedRevision` from the current lockfile at evaluation time. That would make
the check accept every update automatically.

The guard throws a review error when that input changes. This catches recipe
changes and backports even when a package keeps the same version. The portal fix
tracks `hyprland.inputs.xdph`; tracking only the outer Hyprland revision would
miss an independent portal input update.

When a release boundary is known, add `affectedVersions`:

```nix
affectedVersions = {
  from = "1.2.0";
  until = "1.4.0";
};
```

The lower bound is inclusive and the upper bound is exclusive. Both bounds must
be present, and the interval must be nonempty. The guard checks the incoming
package before applying an override that might change its version. A package
outside the interval fails evaluation with the fix name and removal condition.
The fix is never silently applied outside its declared range.

The existing PrismLauncher release override is limited to `[11.0.3, 11.1.0)`.
That is the currently supported incoming range for the already selected 11.1.0
source, not a claim that every older PrismLauncher release is broken. Its Darwin
watch-test patch has a separate lifecycle. The other migrated workarounds have
no confirmed fixed release recorded, so they use revision review triggers.

These triggers are conservative. An input change means review is required; it
does not prove the bug is fixed. Keeping the revision guard alongside a version
range also catches packaging changes within that range. A merged PR or closed
issue is evidence to investigate, not proof that the pinned source includes a
working fix. Record the specific issue or PR URL when one is established.

## Add, check, and retire a fix

1. Add `temporary/<name>.nix`, following an existing record. Put its patch data
   under `temporary/patches/`. Use a concrete removal condition and the revision
   of the input that owns the broken source or recipe.
2. Register the file in `temporary/default.nix`. For package fixes, add application
   and platform conditions to `packages.nix`, overriding the existing attribute.
   Function overrides such as `wrapFirefox` use the same attribute selection.
   Keep permanent overlay composition in `default.nix`. For module fixes, select
   `fixes.apply "<name>" inputs.<upstream>` in the owning module's `imports`.
3. Add a package or module evaluation case in `tests/nix/temporary-fixes.nix`.
   Keep the regression reproduction or upstream test with the fix's evidence.
4. Run `just temporary-fixes-check` after changing a fix or updating inputs.
   The flake check evaluates packages for all three supported platforms. It
   forces revision review for every registered package and module fix, including
   disabled features.
   Normal `nix flake check` and `just update-all` also evaluate this check.
5. When a guard fails, inspect the new pinned source and test the package or module without
   the workaround on the affected platform. If fixed, remove the record, registration,
   application, patch, and obsolete check case together. Remove the attribute
   override from `packages.nix` only when no other customization remains. Keep
   the module's package selection. For module fixes, remove the registered fix's
   import and restore the upstream module. If still
   broken, update the reviewed revision or supported range only after validating
   that the workaround is still needed and works.

The check performs evaluation and tests guard behavior. It does not build every
package or demonstrate runtime correctness. It needs no live GitHub status
request, so normal evaluation remains reproducible and works with cached inputs.
It does not send notifications or poll upstream while the lockfile is unchanged.
