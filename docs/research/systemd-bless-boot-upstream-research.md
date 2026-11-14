# systemd-bless-boot stale-entry research

## What happened locally

The desktop was booted from a counted NixOS entry. Its volatile
`LoaderBootCountPath` EFI variable named that entry, but the entry had been
removed from `/boot/loader/entries` during a later online system switch. A
restart of `systemd-bless-boot.service` then failed with:

```text
Can't find boot counter source file for '/loader/entries/nixos-…+2-1.conf'
```

The resulting non-zero unit status made deploy-rs roll the system activation
back even though the new system had built and otherwise activated correctly.

## Upstream behaviour and prior work

systemd's boot assessment design is intentional: systemd-boot decrements a
counter in the selected entry's file name, records that renamed file in
`LoaderBootCountPath`, and `systemd-bless-boot` removes the counter only after
`boot-complete.target` has been reached. See [the systemd design document](https://github.com/systemd/systemd/blob/main/docs/AUTOMATIC_BOOT_ASSESSMENT.md)
and [the implementation](https://github.com/systemd/systemd/blob/main/src/bless-boot/bless-boot.c).

The generator starts `systemd-bless-boot.service` solely when that EFI variable
exists. It does not verify that the referenced file still exists.
[Source](https://github.com/systemd/systemd/blob/main/src/bless-boot/bless-boot-generator.c).

When the helper cannot find either its counter-bearing source or the expected
target name on a mounted boot partition, it currently returns `EBUSY`. This is
the exact failure observed locally. That error is deliberate in current
systemd, rather than an accidental fall-through.
[Source](https://github.com/systemd/systemd/blob/main/src/bless-boot/bless-boot.c#L497-L557).

There has already been a closely related systemd fix. In 2023, systemd fixed
`systemd-bless-boot` returning failure *after it had successfully renamed* an
entry. That was [systemd PR #28640](https://github.com/systemd/systemd/pull/28640),
linked from [issue #28637](https://github.com/systemd/systemd/issues/28637).
It does not cover a missing source entry. Other public reports show that the
same EFI variable and boot-counting path still has edge cases, including a
missing variable ([#28637](https://github.com/systemd/systemd/issues/28637)),
an unsuffixed-entry conflict ([#33504](https://github.com/systemd/systemd/issues/33504)),
and a current boot-counting regression ([#40405](https://github.com/systemd/systemd/issues/40405)).
None describes the exact NixOS online-pruning sequence.

The closest confirmed precedent is [systemd issue #40386](https://github.com/systemd/systemd/issues/40386).
After a soft reboot, a previously blessed entry no longer had a counter-bearing
source file but the EFI variable still existed, producing the same error.
systemd fixed that case in [PR #40399](https://github.com/systemd/systemd/pull/40399)
by making the generator skip soft-rebooted systems. This confirms that the
service belongs to a real EFI boot transaction, not every way a system manager
can enter or re-enter userspace.

NixOS owns the other half of the interaction. Its systemd-boot builder first
garbage-collects all NixOS entry files that are not in the retained generation
set, then writes the new set.
[Source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/system/boot/loader/systemd-boot/systemd-boot-builder.py#L586-L595).
Its garbage collector does not exempt the entry named by `LoaderBootCountPath`.
[Source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/system/boot/loader/systemd-boot/systemd-boot-builder.py#L620-L637).

NixOS also restarts changed services during a configuration switch by default.
`restartIfChanged` defaults to `true`.
[Source](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/systemd-unit-options.nix#L548-L555).
That makes an otherwise boot-only blessing operation run again after the
builder has pruned its input.

NixOS has tests for boot counting and for garbage collection with boot counting
enabled, but the garbage-collection case gives an old entry artificial counters
instead of booting it with a live `LoaderBootCountPath`. It therefore does not
exercise an online switch while the EFI variable names an entry being removed.
[Source](https://github.com/NixOS/nixpkgs/blob/master/nixos/tests/systemd-boot.nix#L194-L245)
and [boot-counting test](https://github.com/NixOS/nixpkgs/blob/master/nixos/tests/systemd-boot.nix#L777-L890).

## Where the upstream fix belongs

The primary fix should be in nixpkgs, not systemd.

NixOS is the component that chooses to delete the entry during an online
activation. It can see the boot partition, manages the entries it deletes, and
can retain one extra file without changing systemd's cross-distribution policy.
The builder should read `LoaderBootCountPath` when it is available, validate it
as a path below `loader/entries/` for a NixOS entry, and add its counter-bearing,
good, and bad names to the garbage-collection keep set. Keeping only the
literal path is insufficient because a successful blessing has already renamed
it to its good form. This is only for the current boot session. The EFI variable
is volatile and systemd removes the counter when the boot is blessed, so the
temporary extra entry naturally disappears on a later rebuild.

The nixpkgs change should include a VM test that:

1. Boots a counted generation and confirms the EFI variable names it.
2. Lets the first blessing rename the entry while retaining its EFI variable.
3. Makes that generation fall outside `configurationLimit`.
4. Runs the bootloader builder online and forces a unit restart.
5. Verifies the applicable entry name remains and that the unit exits
   successfully.

NixOS should also consider setting `restartIfChanged = false` for
`systemd-bless-boot.service`. The unit is designed to run once per boot and has
`RemainAfterExit=yes`; restarting a completed blessing operation on an ordinary
online switch has no useful work to do. This would stop the immediate failure
path, but it should be a secondary defence. It does not protect a manual restart
or a delayed original blessing, and it leaves a live EFI pointer to a deleted
entry.

## Should systemd change too?

I would file a focused systemd issue with the reproduction and the NixOS fix,
but I would not block on a systemd patch.

systemd could reasonably downgrade the final "counter source file missing"
case to a warning and success for the `good` operation after `$BOOT` is mounted.
At that point the system has reached `boot-complete.target`, and a removed entry
cannot be made bootable again by failing the service. This would make the helper
more tolerant of external boot-entry managers.

That policy has a cost. systemd cannot tell whether another manager deliberately
pruned the entry, an administrator removed it by mistake, or a filesystem view
is incomplete. Turning every missing-entry failure into success would hide an
otherwise useful integrity signal. If systemd accepts a change, it should be
narrow: only `good`, only after all boot locations were searched successfully,
and with a warning that includes the missing path. It should retain failures for
unreadable EFI variables, malformed paths, unavailable boot partitions, and
rename or I/O errors.

The local wrapper follows that narrow policy for this NixOS layout. It is a safe
bridge, but nixpkgs retaining the current boot-session entry and avoiding an
unnecessary restart are the cleaner durable fixes. Once nixpkgs has that
behaviour and its test, the wrapper can be removed.
