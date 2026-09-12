# Test the guide with independent readers

Use a fixed candidate revision and its public starter. Ask each willing reader
to begin with [prerequisites](start-here.md), build the starter, inspect the
result, change a setting, and follow the [recovery guide](update-and-recover.md).
Linux readers can also try the disposable VM. Record the native platform and
whether the reader already knows Nix.

Choose five readers for an initial small pilot. A useful first acceptance target
is four completing the starter without synchronous maintainer help. This is a
proposed target for finding guide defects, not a statistical estimate of general
usability. Do not count automated tests or agent simulations as independent users.

For each session, keep a private record of:

- Candidate revision and whether the source was clean.
- Platform, prerequisites and starting Nix experience.
- Steps completed, elapsed time and help requested.
- The exact step that failed and a redacted error excerpt.
- Whether the reader could explain the change before activation.
- Whether the guide supplied a working recovery route.

Use an anonymous participant identifier in any reviewed public summary. Retain
only the personal information needed to organize the pilot, outside the repository.
Do not request passwords, private configurations or full environment dumps.

Fix repeated blockers, then repeat the affected path with a reader who has not
seen the repair. Do not change the candidate mid-session and count the mixed
result as evidence for one revision.

A release summary can use this table after real results exist:

| Candidate | Platform | Attempted | Completed independently | Repeated blocker | Follow-up |
| --- | --- | --- | --- | --- | --- |
| Not yet studied | Not yet studied | 0 | 0 | No observations collected | Recruit willing readers after candidate checks pass |

Reader recruitment and publishing findings are separate external actions. The
repository supplies the protocol; it does not claim a completed user study.
