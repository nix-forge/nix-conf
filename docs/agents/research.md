# Research notes and evidence

Use this guide when running `mattpocock-research` or saving investigation results.
The [publication policy](../publication.md) governs every output, including work
delegated to a background agent.

## Produce a reusable answer

1. Name the question, the affected component, and the decision the evidence
   needs to support. Find existing notes with `rg --files docs` before creating
   another one. Update a note when the question is the same; distinguish a new
   investigation from an older dated result.
2. Investigate primary sources. For installed tools or skills, inspect the
   actual installed version and its source. For upstream behavior, record the
   revision, release, or retrieval date. Separate observations, source claims,
   and inferences; retain uncertainty and contradictory results.
3. Write one Markdown draft using the [research template](../templates/research.md).
   Use `.scratch/<topic>/research.md` for a local redacted draft when publication
   is not yet appropriate. Put raw traces, discussion exports, and personal
   context outside the repository.
4. Review the draft for relevance, sources, portable paths, and personal data.
   Keep durable public notes at `docs/<topic>-research.md`, or in an existing
   topic directory. Preserve existing names and links unless a move is needed.
   Publish a small redacted capture under `docs/assets/<topic>/` only when the
   note cannot convey the evidence adequately on its own.

Research is complete when it answers the question or identifies the specific
unresolved gap, links the sources for its material claims, and records the
limits of any tests. An aggregate pass does not erase a crash, skipped check,
or untested platform. A source link does not establish that its advice was
tested locally.

## Keep outputs in the right place

| Output | Location and lifetime |
| --- | --- |
| Reusable findings | Reviewed Markdown under `docs/`; update when the question is revisited. |
| Essential visual or text evidence | Small reviewed files under `docs/assets/<topic>/`, linked from a note. |
| Redacted spec, issue, or research drafts | Ignored `.scratch/<topic>/`; local to this clone. |
| Raw logs, crash dumps, environment captures, private discussion | Restricted storage outside the repository; keep only as long as needed. |
| Cross-session handoff | A redacted file in a private temporary directory outside the workspace, as the handoff skill requires. |
| One-off wizard and captured credentials | Private temporary or state storage outside the repository. Promote only an explicitly requested reusable script after review. |

Ignoring a file prevents ordinary Git staging; it does not encrypt it or exclude
it from every filesystem copy or `path:` flake input. Even local drafts in
`.scratch/` should already be redacted. Follow the publication policy before
copying any of them into an issue, PR, committed document, or another task.
