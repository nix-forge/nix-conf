# Release evidence

Candidate: `<REVISION>`
Tracked-source SHA-256: `<TREE_DIGEST>`
Recorded: `<UTC_DATE>`

Include lockfile and submodule identities from the private validation record.
A dirty candidate needs its content digest and a clear local-only label. Publish
a clean, reviewable revision before presenting a release as reproducible.

| Target | Native platform | Phase | Result | Evidence date | Remaining requirement |
| --- | --- | --- | --- | --- | --- |
| Public starter | x86 Linux | Build and console VM | Pending | Pending | Candidate-specific result |
| Public starter | ARM Linux | Native build | Pending | Pending | Candidate-specific result |
| Public starter and Darwin example | Apple Silicon | Native build | Pending | Pending | Candidate-specific result |
| Graphical demo | x86 Linux | VM workflows | Pending | Pending | Compositor, terminal and configured probe results |
| Personal Linux workstation | x86 Linux | Full build, activation, runtime | Pending | Pending | Each required hardware workflow |
| Personal Mac | Apple Silicon | Full build, activation, runtime | Pending | Pending | Native application and permission checks |
| Application recovery | Declared recovery target | Restore and application use | Pending | Pending | Restored data, writers and credentials |

Replace pending entries only with results actually observed for this candidate.
Use `just validation-manifest` and the evidence status command to discover required
checks. A missing result is incomplete. Do not infer activation from a build,
hardware support from a VM, or application recovery from a successful file copy.

Summarize known regressions, skipped checks and compatibility boundaries. Link
the appropriate guide and reviewed source. Keep raw command logs, private paths,
network details, credentials and reader identities outside the published report.

Record reader-pilot results separately. Automated consumer tests do not establish
that independent readers can follow the guide without assistance.
