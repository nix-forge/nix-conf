# Build and release the guide

The Markdown under `docs/guide/` and `docs/README.md` is the source for the website
and remains readable on GitHub. MkDocs and its search plugin come from the root
Nixpkgs pin. The build publishes only the selected guide pages and reviewed assets.

## Build locally

```sh
nix build .#documentation
python3 -m http.server 8000 --directory result
```

Open `http://localhost:8000/` to read the built guide. Stop the local server with
Ctrl+C when finished. The static output does not need a JavaScript package manager,
a server application, or a database.

The build rejects missing internal pages and anchors. Embedded source examples
use `include` markers around ordinary Markdown fences; the build compares them
with their source. To refresh them deliberately after a source change, use the
pinned documentation shell and the synchronization command in `site/README.md`.

## Prepare a guide release

Run the public examples, native checks for advertised platforms, documentation
build, and publication checks on the proposed revision. Record evaluation, build,
and runtime results separately. Explain compatibility changes and keep the
known-good lockfiles with the release.

The Pages workflow builds the same documentation package and deploys the artifact
only from the trusted default branch through the `github-pages` environment.
GitHub Pages must use GitHub Actions as its publishing source. A local build does
not mean the website has been deployed or a release has been published.

A release should include the source revision, tested starter pins, supported
platforms, completed checks, known limitations, and upgrade guidance. Do not claim
independent reader validation until real readers have attempted the tutorial.

## Maintain evidence

Review captures and their metadata under the
[publication policy](https://github.com/nix-forge/nix-conf/blob/main/docs/publication.md).
Keep raw screenshots and private traffic exports outside the repository. New
rendered images must describe their actual capture or test context.

## Candidate validation evidence

Use [validation records](validation.md) to bind test results to the candidate
source and native platform. The
[release evidence template](https://github.com/nix-forge/nix-conf/blob/main/docs/templates/release-evidence.md)
keeps missing and skipped checks visible. Review any exported summaries for
publication safety; raw logs remain private. A successful guide build is not
proof of workstation activation or hardware behavior.

The [reader-pilot protocol](reader-pilot.md) records actual outsider completion
and repeated blockers. Publish those results only after real sessions occur.
