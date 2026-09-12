# Building the public guide

The root `documentation` package builds the curated guide using pinned MkDocs.
The website publishes `docs/README.md`, `docs/guide/`, two reviewed font captures,
and the local stylesheet. The Nix build also inserts the declared feature catalog
and option reference into their guide pages. Research notes and other repository files remain linked
on GitHub instead of being copied into the site artifact.

```sh
nix build .#documentation
python3 -m http.server 8000 --directory result
```

The source Markdown remains ordinary GitHub-readable Markdown. Where a complete
starter source file appears in a guide, an explicit include marker lets the build
reject drift. Update those fences deliberately with:

```sh
nix develop .#docs --command python site/build.py --update-snippets
```

For a quick local documentation build without generated reference insertion:

```sh
nix develop .#docs --command python site/build.py --output dist
```

`site/mkdocs.yml` owns the navigation and strict validation. Use normal relative
Markdown links between guide pages. Links to source or research outside the
published guide should point to the corresponding GitHub page. This avoids
changing the meaning of source links during generation.

The selected built-in theme supplies responsive navigation, local search, and
keyboard controls. The small stylesheet uses the workstation's dark blue and
mint colors without requiring external fonts or a frontend package manager.

See [implementation research](../docs/public-guide-implementation-research.md)
for the primary sources and [release guidance](../docs/guide/maintaining.md).

Use the Nix `documentation` build when checking the complete release artifact.
It supplies `feature-catalog` and `feature-options` to the renderer, so changed
module defaults appear in the reference. The source-page markers remain readable
on GitHub and explain how to obtain generated output. The build rejects missing
or duplicated markers, and renders regular-expression option types as code.
