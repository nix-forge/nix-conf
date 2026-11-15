# Nix attribute defaults and GitHub merge queues

## Nix `standalone` filtering

`home.standalone or true` is an attribute selection with a default, not boolean
disjunction. Nix defines its syntax as `attrset . attrpath [ or expr ]`; attribute
selection has precedence 1, while boolean OR is spelled `||` and has precedence
13. The expression therefore selects `home.standalone`, returning `true` only
when that attribute is absent. [Nix operator reference](https://nix.dev/manual/nix/2.35/language/operators.html#attribute-selection)

Use this form for homes that are standalone by default:

```nix
lib.filterAttrs (_: home: (home.standalone or true)) homesById
```

The parentheses document the predicate boundary but do not change its semantics.
An explicitly supplied `false` remains false. The default only covers a missing
attribute; the module schema should continue to require a Boolean when the
attribute is present. If the intended policy is opt-in rather than backward
compatible, use `(home.standalone or false)` instead.

## Merge queue and auto-merge

On a branch that requires a merge queue, `gh pr merge` queues a PR only after its
required checks pass. If they have not passed, it enables auto-merge instead;
GitHub adds the PR to the queue once it meets the requirements. `--admin` bypasses
the queue. [GitHub CLI manual](https://cli.github.com/manual/gh_pr_merge),
[GitHub merge-queue guide](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/merging-a-pull-request-with-a-merge-queue)

Required GitHub Actions checks must run for the merge-group SHA as well as the PR:

```yaml
on:
  pull_request:
  merge_group:
    types: [checks_requested]
```

`merge_group` is separate from `pull_request` and `push`; omitting it means the
required check is not reported for the queued merge group and the merge fails.
[GitHub's merge-queue workflow guidance](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue#configuring-continuous-integration-ci-workflows-for-merge-queues)

### Verifying a PR is queued

Auto-merge enabled is not proof of queue membership. Query the documented
GraphQL `PullRequest.mergeQueueEntry`: a non-null entry is the authoritative
queued state and includes `position`, `state`, and `enqueuedAt`. The separate
`autoMergeRequest` field shows whether auto-merge is enabled.
[GitHub GraphQL schema](https://docs.github.com/en/graphql/reference/pulls)

```sh
gh api graphql \
  -f query='query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){autoMergeRequest{enabledAt mergeMethod} mergeQueueEntry{position state enqueuedAt} mergeStateStatus}}}' \
  -F owner=OWNER -F repo=REPO -F number=PR_NUMBER
```

Expect a non-null `mergeQueueEntry`; its state is one of the schema-defined queue
states, for example `QUEUED` or `AWAITING_CHECKS`. Also inspect the PR timeline
or base branch's queue view, which GitHub documents as the UI methods for viewing
queue membership. [Viewing merge queues](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/merging-a-pull-request-with-a-merge-queue#viewing-merge-queues)
