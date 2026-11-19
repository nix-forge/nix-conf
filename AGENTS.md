# Repository instructions

## Agent skills

Before changing configuration or code, read `CONTRIBUTING.md` for repository
boundaries, module conventions, and validation. When choosing or running a Matt
Pocock workflow, read `docs/agents/workflows.md`.

For issues, specs, or review requirements, use `docs/agents/issue-tracker.md`.
For domain exploration or terminology changes, read `docs/agents/domain.md`,
then the relevant glossary terms and existing decisions.

For work spanning sessions or parallel writers, read `docs/agents/coordination.md`.
Maintain the task brief yourself and pass it to workers and reviewers.

## Desktop build placement

Run the full `nixosConfigurations.desktop` build on the host named `desktop`.
Choose the command by caller location:

- On `desktop`, use `just os-build desktop` to build or `just os-switch desktop`
  to build and activate.
- From another host, use `just desktop-build` for a remote build with dry
  activation or `just desktop-deploy` to build and activate remotely.

Evaluation-only commands may run anywhere. The native Linux builder remains
available for isolated Linux packages and checks, not the desktop system
closure. Use the host's configured compiler parallelism.

## Public documentation

Before adding or updating docs, glossaries, issues, screenshots, or captured output,
read `docs/publication.md`. Publish portable technical explanations and reviewed
evidence; keep personal context and raw captures in private local storage.
For research notes specifically, also read `docs/agents/research.md`.
