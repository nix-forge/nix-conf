# Repository instructions

## Agent skills

Before changing configuration or code, read `CONTRIBUTING.md` for repository
boundaries, module conventions, and validation. When choosing or running a Matt
Pocock workflow, read `docs/agents/workflows.md`.

For issues, specs, or review requirements, use `docs/agents/issue-tracker.md`.
For domain exploration or terminology changes, read `docs/agents/domain.md`,
then the relevant glossary terms and existing decisions.

## Desktop build placement

Run the full `nixosConfigurations.desktop` build on the host named `desktop`.
From another host, use `just desktop-build` for a build with dry activation or
`just desktop-deploy` to build and activate. Evaluation-only commands may run
anywhere. The native Linux builder remains available for isolated Linux
packages and checks, not the desktop system closure.

## Public documentation

Before adding or updating docs, glossaries, issues, screenshots, or captured output,
read `docs/publication.md`. Publish portable technical explanations and reviewed
evidence; keep personal context and raw captures in private local storage.
For research notes specifically, also read `docs/agents/research.md`.
