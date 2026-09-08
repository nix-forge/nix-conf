# Hyprland validation evidence

The reviewed results and their limitations are recorded in
[the validation note](../../hyprland-upstream-local-validation.md).

The baseline failed deep-ancestry and mapped parent-teardown cases. The fixed
native run reported nine passing cases, followed by the documented test-harness
shutdown crash artifact. The independent protocol run recorded clean shutdown.
These are historical results, not tests rerun during the publication cleanup.

Raw environment dumps, downloaded discussions, crash reports, executable copies,
and local worktree snapshots remain in the owner's ignored copy of this directory.
The current tree tracks only this index; earlier commits may retain older captures.
Reproduce the tests using the
checked-in test sources and upstream revision recorded in the validation note.

The public code and test changes are available in the repository's
[Hyprland patches](../../../modules/nixos/desktop-envs/patches/) and
[regression tests](../../../tests/hyprland/).
