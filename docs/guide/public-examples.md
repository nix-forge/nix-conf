# Public example and consumer checks

The independent [Home Manager starter](first-configuration.md) uses stable 26.05
Nixpkgs and Home Manager pins. The [Apple silicon example](darwin-example.md)
uses its own stable 26.05 Nixpkgs and nix-darwin pins. The graphical demo and
reusable-module consumers use the workstation's current unstable inputs.
These checks do not promise compatibility with arbitrary release combinations.

## Exercise the candidate's public interfaces

From a checkout with initialized submodules and new source files added to Git:

```sh
bash tests/public-guide/check-consumers.sh
```

On the desktop host, prefix that command with `workstation-task`. The script
needs Nix, Git, jq, and ordinary shell utilities. It captures the candidate source
in the Nix store, initializes `templates.starter` and `templates.darwin` through
`nix flake init`, and compares the extracted contents with the exported source.
The starter then builds with its own unchanged lockfile. Darwin builds only on
Apple silicon; other platforms evaluate its system derivation and assertions.

Two separate temporary consumer flakes exercise the Git, file-search, and prompt
recipes. The first uses an actual `flake = false` source input, as documented in
the [Git recipe](git.md). The second imports these typed exports:

```nix
inputs.nix-conf.modules.homeManager.dev-git
inputs.nix-conf.modules.homeManager.shells-fzf
inputs.nix-conf.modules.homeManager.shells-integration
inputs.nix-conf.modules.homeManager.shells-starship
```

For typed imports, use
`git+https://github.com/nix-forge/nix-conf?submodules=1` as the input URL. They
load the root flake and its inputs. Source-file imports need neither submodules
nor evaluation of the complete root flake. The source consumer's Nixpkgs and
Home Manager inputs are overridden to the captured candidate's exact versions,
so an unrelated upstream update cannot decide the result.

Both consumers parse the actual generated Git and prompt configuration and
exercise Git status and file search. They force Home Manager assertions.
The typed contract covers these four names, not every discovered module or a
promise that any arbitrary module works without its declared dependencies.

Pass an explicit candidate flake and system to reproduce another source:

```sh
bash tests/public-guide/check-consumers.sh \
  'git+https://github.com/nix-forge/nix-conf?submodules=1&rev=<REVISION>' \
  x86_64-linux
```

The candidate supplies its own fixtures and exported templates. Untracked files
are excluded by Nix's Git source filtering. Keep the candidate revision or dirty
source identity with the result. The script also runs the starter's VM test on
native x86 Linux. Run the graphical demo test separately. Consumer package checks
do not establish graphical VM boot,
physical workstation behavior, Darwin activation, or an independent reader's
ability to follow the guide.
