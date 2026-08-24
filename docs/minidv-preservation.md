# MiniDV preservation on the desktop

This workflow creates an untouched raw-DV (`.dv`) master from a Sony DCR-TRV19
over its native i.LINK/IEEE-1394 connection. The master is the preservation
copy. H.264 MP4 files are separate, disposable viewing derivatives.

## Safety model

- Never capture directly into an existing tape directory. The capture utility
  refuses it rather than overwriting or silently resuming a prior attempt.
- Do not use autosplit, `--rewind`, or any tape operation other than the normal
  VCR playback/start-stop behavior required for capture.
- Do not enable legacy FireWire drivers, disable IOMMU, change firmware/BIOS,
  or use a USB-to-FireWire adapter.
- Use the camera's AC adapter, not an old battery.
- First use a non-critical tape and inspect it manually before handling family
  tapes. Avoid extra complete tape passes.
- A raw master is not considered preserved until there is a checksum-verified
  copy on a separate physical device. iCloud Photos is not an archival copy.

The desktop uses Linux's normal `firewire_ohci` and `firewire_core` stack. The
PCI class alias automatically loads the driver when an OHCI-compatible
controller is enumerated; no forced module load is configured. The installed
TI TSB43AB23 controller's local `fw*` device receives a logind `uaccess` ACL
only for the active local session. The rule is restricted to PCI vendor/device
IDs `104c:8024`; it leaves the device mode unchanged and does not grant access
to other FireWire devices. Its `70-` filename ensures systemd's normal seat and
`uaccess` rules process the tag afterward.

## Physical installation

1. Shut the desktop down completely and disconnect AC power. Do not install a PCIe card while the computer is powered.
2. Use normal ESD precautions. Install the FebSmart FS-FW400 in a suitable free PCIe slot. A PCIe x1 card can use a compatible larger slot, but check actual GPU clearance and installed expansion cards first.
3. Reconnect AC power and boot NixOS. Do not change Windows, partitions, bootloader, Secure Boot, firmware, or BIOS settings for this workflow.
4. Before connecting a valuable tape, run `minidv-diagnose`. Success at this stage means `lspci -nnk` identifies the actual controller and says `Kernel driver in use: firewire_ohci`; it is more authoritative than the card's advertised chipset.
5. Connect the AC-powered camcorder with the 4-pin-to-6-pin FireWire cable, switch it to VCR/playback mode, then run `minidv-diagnose` again. A working bus has a local `fw*` node (`is_local=1`) and a remote node (`is_local=0`) under `/sys/bus/firewire/devices/`.

If the report shows a controller but not the camera, check the cable and VCR
mode before considering software changes. If it shows the camera but the normal
desktop user cannot read/write `/dev/fw*`, keep the report and inspect
`udevadm info`/`getfacl`; do not use `chmod` or a world-writable rule.

## First capture

The deployed utility uses the pinned `dvgrab` options below:

```text
--format raw --size 0 --frames 0 --showstatus --srt
```

`raw` stores the DV stream unmodified. `--size 0` and `--frames 0` remove the
default split limits; autosplit is intentionally not enabled. `--srt` creates
sidecars containing recording date/time data where the DV stream provides it;
it does not modify the master.

Capture a test tape first, using an absolute archive root with at least 20 GiB
free:

```sh
minidv-capture tape-test-001 /home/ianmh/MiniDV
```

The resulting layout is:

```text
MiniDV/tape-test-001/
  master/tape-test-001.dv
  master/tape-test-001.dv.sha256
  logs/capture.log
  logs/ffprobe-<UTC>.json
  logs/ffprobe-<UTC>.txt
  logs/verify-<UTC>.log
  metadata/capture-info.txt
  metadata/tape-test-001-001.srt0   (only if DV date/time was available)
  metadata/tape-test-001-001.srt1   (only if DV date/time was available)
```

The tool takes a directory lock, requires a remote FireWire node, retains
partial files on failure/interruption, writes an initial capture metadata file,
and runs verification after `dvgrab` succeeds. It deliberately leaves an
interrupted or failed capture in place. Do not reuse that tape ID; inspect it
and choose a new ID for another attempt.

Start `minidv-capture`, wait until `dvgrab` is waiting for DV, then press Play
on the AC-powered camcorder in VCR mode. The capture command deliberately uses
`--noavc --nostop`, so it never issues camera play or stop commands. Let
`dvgrab` stop automatically at the tape end. `Ctrl-C` is an abort, not the
normal completion method; it intentionally leaves the output marked incomplete.
The wrapper now controls `dvgrab` as a direct child: one `Ctrl-C` records the
interruption and tries `SIGINT`, then `SIGTERM`, then a last-resort `SIGKILL`
only for the stalled capture process. It never removes partial files.

## AMD-Vi IOMMU capture fault

The first Sony capture on this desktop exposed repeated `firewire_ohci`
AMD-Vi IOMMU page faults and then stalled. This is a real capture-integrity
failure, not a condition to work around by disabling IOMMU or enabling
passthrough/identity DMA.

Do not try to solve a FireWire fault by disabling IOMMU or using IOMMU
passthrough. Keep the normal desktop configuration unchanged until a
controller-specific, tested upstream-compatible fix has been established.

Before touching an important tape, confirm the current boot and collect a
fresh diagnosis:

```sh
cat /proc/cmdline
minidv-diagnose
```

Capture another short, non-critical test tape under a new ID only after the
underlying fault has been resolved. A successful result must have no new
FireWire AMD-Vi page-fault storm, no capture stall, and no unexplained dropped
frames. If the fault recurs, stop testing with family tapes and retain the
diagnostics; do not add `iommu=pt`, `iommu.passthrough=1`, or `amd_iommu=off`.

## Verify and back up

Run verification again whenever a master is copied or before transcoding:

```sh
minidv-verify /home/ianmh/MiniDV/tape-test-001
```

It verifies non-empty raw DV, expected DV video and audio streams, format
details, the checksum, and capture-log warnings. It also tells you to inspect
the beginning, middle, and end manually. A zero exit code is useful evidence,
not a substitute for watching those samples.

### Ending a whole-tape capture

DV over FireWire does not provide a reliable end-of-tape event; an ended tape
and a paused tape both simply stop sending DV frames. The capture utility
therefore deliberately does not use an arbitrary no-frame timeout, which could
silently truncate a capture after a long pause. When the camcorder physically
reaches its end, press `Ctrl-C` once. The raw file and sidecars are retained,
but remain marked incomplete until you explicitly assert that the tape did end:

```sh
minidv-finalize --confirm-tape-ended /home/ianmh/MiniDV/tape-test-001
```

This command refuses an active capture or existing master, does not modify any
DV bytes, and runs the normal verification/checksum workflow. Do not use it if
you stopped partway through a tape. This deliberate finalization step is safer
than guessing based on an arbitrary idle period.

Make a second copy on a separate physical disk without overwriting an existing
directory, then verify its manifest from that copy:

```sh
rsync -a --protect-args --info=progress2 \
  /home/ianmh/MiniDV/tape-test-001/ /media/backup/MiniDV/tape-test-001/
(cd /media/backup/MiniDV/tape-test-001/master && sha256sum --check tape-test-001.dv.sha256)
```

Keep the tape and both raw master copies. Add a third, off-site copy when
practical.

## Apple-compatible derivative

After the master passes verification, create a distinct viewing copy:

```sh
minidv-transcode /home/ianmh/MiniDV/tape-test-001
```

It probes the actual video standard, field order, and display aspect ratio,
then uses FFmpeg's `bwdif=mode=send_field:parity=auto:deint=all` with H.264,
AAC, `yuv420p`, CRF 18, and `+faststart`. Field-rate deinterlacing produces
roughly 59.94p for NTSC DV or 50p for PAL DV without hardcoding either. The
`.dv` master is checksum verified first and is never changed.

When the capture has a `metadata/*.srt0` sidecar, `minidv-transcode` derives a
candidate clip manifest from significant DV recording-clock discontinuities.
`srt0` is used because it follows the continuous master timeline; `srt1` may
restart when the tape timecode restarts. The utility preserves an opening range
with an invalid camera clock as an `unknown-date` clip, ignores brief metadata
glitches, and marks every extracted recording date as *inferred* rather than
authoritative.

Each run writes new files without overwriting an earlier derivative:

```text
metadata/clip-manifest-<UTC>.tsv
derivatives/apple/clips/<UTC>/clip-manifest.tsv
derivatives/apple/clips/<UTC>/<tape-id>-clip-<NNN>-<date-or-unknown>.mp4
derivatives/apple/clips/<UTC>/SHA256SUMS
```

The MP4 clips retain the original display aspect ratio, all source audio
streams, and field-rate progressive video. For a credible DV date, the tool
adds QuickTime/Apple creation-date metadata using the desktop's configured
time zone and records that assumption beside the run. Do not treat a camera's
date as correct merely because it is embedded: review the manifest boundaries
and at least a few seconds on both sides of every boundary before importing.
If a tape was recorded in another time zone, correct its date in Apple Photos
after review rather than silently changing the raw master or sidecar.

### Optional high-quality upscale before delivery encoding

For a larger, high-quality viewing derivative, first create a separate
intermediate run:

```sh
minidv-upscale /home/ianmh/MiniDV/tape-test-001
```

This is a deterministic, non-AI workflow: FFmpeg applies field-rate `bwdif`
deinterlacing, then zimg Lanczos scaling to twice the stored raster dimensions,
while retaining the DV sample aspect ratio. Thus 4:3 NTSC DV (720×480, SAR
8:9) becomes 1440×960 with SAR 8:9 and still displays as 4:3. Each candidate
clip is written as ProRes 422 HQ video with PCM audio beneath
`derivatives/upscaled/clips/<UTC>/`. It conservatively requires about 50 MB of
free space per source second—roughly 132 GB for a 44-minute tape—so it fails
before encoding if the destination filesystem is too small.

After reviewing representative intermediates for natural faces, moving edges,
and scene cuts, transcode that explicit run to compact Apple-compatible MP4s:

```sh
minidv-transcode /home/ianmh/MiniDV/tape-test-001 \
  --upscale-run /home/ianmh/MiniDV/tape-test-001/derivatives/upscaled/clips/<UTC>
```

The second command does **not** deinterlace or enlarge again. It produces
H.264/AAC, `yuv420p`, CRF 16 delivery files in
`derivatives/apple/upscaled-clips/<UTC>/`, preserving the clip boundaries,
display aspect ratio, and inferred QuickTime creation dates. Treat both the
ProRes and MP4 files as optional derivatives; retain the unmodified `.dv`
master and checksum-verified backups.

Topaz Video's Dione DV model is a separately licensed interactive option for
AI enhancement. If you use it, work from a copy of a raw-DV clip, compare a
short representative test against this deterministic baseline, and keep only
results that do not introduce flicker, altered faces, or invented detail.

## Mac mini and Apple Photos handoff

1. Transfer the complete tape directory over the LAN or on a shuttle disk. exFAT is acceptable for a cross-platform transfer disk, but is not the only archival copy.
2. On the Mac, verify the raw master before relying on the transfer with `cd /path/to/tape-test-001/master && shasum -a 256 --check tape-test-001.dv.sha256`. New manifests use a relative master filename, so they remain valid after copying the tape directory.
3. Keep raw `.dv` masters outside Apple Photos and retain the independent backups.
4. Import only reviewed H.264/AAC clips from `derivatives/apple/clips/<UTC>/` into Apple Photos. Correct dates only where the tape's original date is reliable, enable iCloud Photos, and confirm upload/synchronization before considering that viewing stage complete.

Tape-era still-photo recordings are preserved as normal DV footage during this
workflow. If desired later, extract a chosen frame into PNG or a high-quality
photo derivative; do not do that during archival capture.

## Acceptance checklist

Do not begin an important-tape pass until a non-critical test tape establishes
all of the following:

- [ ] `lspci -nnk` shows the installed controller and `firewire_ohci` is its
  bound driver.
- [ ] The current boot has a local FireWire sysfs node and the connected Sony
  appears as a remote node.
- [ ] The normal desktop user can access the required `/dev/fw*` node through
  its existing ACL; no broad permission workaround was used.
- [ ] A short capture writes one non-empty raw `.dv` file with `dvvideo` and
  audio identified by `ffprobe`.
- [ ] The capture log has no unexplained dropped/damaged-frame or serious-error
  indication.
- [ ] A SHA-256 manifest has been generated and verifies successfully.
- [ ] Beginning, middle, and end samples have been played and inspected.
- [ ] A separate physical-disk copy verifies against the same checksum.
- [ ] A separate H.264/AAC MP4 derivative has been created and plays with the
  original display aspect ratio.
- [ ] The Mac copy verifies before the MP4 derivative is imported into Apple
  Photos, and the raw masters remain independently backed up outside Photos.

## Troubleshooting order and rollback

Diagnose in order: PCIe enumeration, `firewire_ohci` binding, FireWire bus and
camera, cable/VCR mode, permissions, AV/C control, `dvgrab`, storage throughput,
then capture integrity. `minidv-diagnose` gathers the safe evidence needed for
each stage.

The NixOS changes add the capture packages/scripts and a narrow logind-ACL udev
rule for the installed TI controller. They do not disable IOMMU, enable
FireWire remote DMA, change firmware/BIOS, or touch Windows. To remove the
workflow entirely, remove the MiniDV host module/scripts, rebuild, and keep
all captured files untouched.
