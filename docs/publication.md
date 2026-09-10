# Publishing documentation

For skill-generated research, drafts, handoffs, and wizards, follow the
[artifact workflow](agents/research.md) as well as this policy.

Write research notes for a public reader. Keep the technical question, findings,
source links, reproduction steps, and limitations. Use repository-relative links
and `$HOME`, `<USER>`, or `<HOSTNAME>` for local examples. Resolve these placeholders
against the actual configuration before running a command.

Use the owner's public handle and GitHub noreply address for public attribution.
Keep personal email addresses, device serials, Bluetooth addresses, private
network names, account-specific anecdotes, and credential locations out of prose
unless the detail is necessary and the owner explicitly chooses to publish it.
Functional account and host names in deployment configuration remain authoritative.

Private project names and business domains must stay out of public filenames,
templates, fixtures, and prose. Use neutral identifiers. When an application
requires a private identifier, encrypt it with the private value or settings bundle rather than exposing it
in a template or filename.

Store raw environment dumps, crash reports, upstream discussion exports, build
trees, caches, and personal notes outside this repository. Existing local research
captures under the ignored evidence directory remain available to their owner.
Publish a small redacted excerpt or a result summary with links to primary sources.
Mark redacted captures as such; retain original checksums only when explaining
which original input they identify.

Before staging an image, inspect its full contents and metadata for account pages,
messages, notifications, tab titles, location data, and credentials. Secret scanners
do not inspect the visible text in screenshots. The existing reviewed font and
emoji test images are suitable examples of narrowly captured evidence.

Before committing, inspect `git diff --cached` and run the repository's Gitleaks
hook. Its documentation rules reject personal home paths, common personal email
providers, and hardware identifiers in docs. They supplement credential scanning;
they cannot decide whether a personal story belongs in public. Keep exceptions
narrow and source-backed.

CI scans Git history and the complete committed tree with the same policy. Six
reviewed immutable historical commits have exceptions for the four publication
metadata rules only. Credential rules still scan those commits, and the full
publication policy still checks their surviving files in the current tree.
Canary tests verify both scopes and that the historical exceptions cannot hide
credentials. This cleanup does not rewrite published history.

Set a repository-local public identity when making a new checkout:

```sh
git config --local user.name IanHollow
git config --local user.email 72767437+IanHollow@users.noreply.github.com
```

Encrypting a Git configuration or adding a mailmap does not remove author and committer identities already embedded
in old commits. Rewriting published history requires coordinating affected branches,
open pull requests, and other clones before a force push.

Both home profiles select the same protected GitHub noreply identity for Git and
Jujutsu, including in repositories without a remote. Two configured Git checks
use the encrypted policy described in [the secret-management guide](secrets.md):

- `email-privacy-commit` runs at `commit-msg` to catch private identities, staged
  content, and commit messages early.
- `email-privacy-push` runs at `pre-push` to inspect outgoing history, including
  deleted file content, commit metadata, reference names, and annotated tags.

Git 2.55 or newer runs these configured checks alongside ordinary repository
hooks. They do not replace `core.hooksPath` or require changes to hook installers.
Git runs the ordinary filesystem hook last, so a later hook can modify a message
or staged content after the early check; the outgoing-history check catches that
before publication. See [Git's hook documentation](https://git-scm.com/docs/git-hook).

These are local safeguards. `--no-verify`, disabled configured hooks, alternate
Git clients, GitHub API calls, and browser edits can bypass them. Review pull
request bodies and other web content before publishing. Each machine needs the
home configuration and its signed secrets.
