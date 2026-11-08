# Automatic AV1 transcoding for a media library

Reviewed: 2026-09-24. Scope: AV1 conversion of already-downloaded video files
for a self-hosted media server; upstream documentation retrieved on the review
date.

## Answer

Automatic AV1 conversion is technically feasible in 2026 when the worker has a
supported hardware encoder, but it is not a safe library-wide default. It can
reduce storage and delivery bitrate for files that are larger than the selected
quality target, at the cost of a second lossy video generation, substantial
one-time compute and a higher chance that a playback client will require
Jellyfin to transcode the file again. The benefit therefore depends on measured
size reduction and direct-play results for the actual clients.

Use a queued, non-destructive pilot: create AV1 copies of a deliberately varied
sample, retain the sources, and promote only outputs that are smaller and pass
visual, metadata, and client playback checks. Keep a compatible source for
Dolby Vision, HDR, subtitle-heavy, and remote-client use until those cases have
been tested. This recommendation is an inference from the documented codec and
client variability below; it is not a claim that a particular AV1 setting will
save a fixed percentage.

For new acquisitions, first consider a suitable already-efficient release when
the existing quality policy and client support allow it. This avoids another
lossy encode and the temporary space needed for two copies. Do not give AV1 a
blanket preference without checking release quality and playback.

## Current storage policy

Updated 2026-10-04. Automatic library-file transcoding has been removed.
Library files retain their downloaded video, audio, and HDR metadata. Jellyfin
streaming transcoding remains enabled for clients that need it; it does not
replace library files. The research and pilot recommendations below are
background information, not an enabled conversion workflow.

The removed worker had not converted any full library files. Its last scan
reported only recent imports and no conversion jobs. The worker's empty job
workspace and temporary benchmark copies were removed. No original library
files needed restoration.

Radarr and Sonarr completed-download cleanup remains independent of transcoding:
successfully imported jobs are removed after the client reports seeding complete
and the torrent stopped. Removing a download hardlink leaves its library file
intact. See [Servarr completed download handling](https://wiki.servarr.com/radarr/settings#completed-download-handling).

## Findings and sources

### What an AV1 conversion changes

- AV1 has a normative [bitstream and decoding specification](https://aomedia.org/specifications/av1/).
  The AOM AV1 tool description says quantization index zero uses a quantization
  step of one, a lossless coding mode ([AOM AV1 tool description, v1.1](https://aomedia.org/docs/AV1_ToolDescription_v11-clean.pdf)).
  Lossless AV1 is therefore possible in the codec.
- Lossless AV1 does not restore data discarded by an existing H.264, HEVC, VP9,
  or other lossy input. A normal library conversion uses a non-zero quantizer or
  constant-quality target and is lossy. FFmpeg documents `crf` and `qp` ranges
  for its SVT-AV1 wrapper, and says that a higher preset is faster with lower
  quality ([FFmpeg codecs documentation](https://ffmpeg.org/ffmpeg-codecs.html#libsvtav1)).
  This is a source fact about controls; the consequence for an already-lossy
  source is an inference from lossy re-encoding.
- FFmpeg's libaom and SVT-AV1 wrappers are optional build features: the former
  needs `--enable-libaom`, and the latter needs `--enable-libsvtav1`
  ([FFmpeg external-library documentation](https://ffmpeg.org/general.html#Alliance-for-Open-Media-AOM),
  [FFmpeg SVT-AV1 documentation](https://ffmpeg.org/ffmpeg-codecs.html#libsvtav1)).
  Installed FFmpeg availability must be checked before choosing an automation.
- Storage and quality are encoder, preset, source, and target dependent. Intel
  says AV1 encoder controls can improve quality at a bitrate or decrease bitrate
  for a quality target ([Intel Media Engine Hardware](https://www.intel.com/content/www/us/en/docs/oneapi/optimization-guide-gpu/2024-2/media-engine-hardware.html)).
  AMD makes a similar product claim for RX 7000 AV1 at lower bitrates and smaller
  files ([AMD Radeon RX 7000](https://www.amd.com/en/products/graphics/desktops/radeon/7000-series.html)).
  Neither source establishes a universal saving for existing media, so size and
  quality must be measured per chosen policy.

### Playback and format risks

- Jellyfin selects Direct Play only when container, video, audio, and subtitles
  are all compatible; an unsupported video codec causes video transcoding.
  Subtitles may be remuxed or burned in, and burn-in causes video transcoding
  ([Jellyfin codec support](https://jellyfin.org/docs/general/clients/codec-support/)).
  Thus converting only video to AV1 does not ensure Direct Play, and copying
  existing audio and subtitle streams does not make every client compatible.
- Jellyfin's current client table marks AV1 as fully supported in Chrome, Edge,
  Firefox, Android, Roku, Kodi, and Jellyfin Media Player; support depends on
  the device/settings in Safari, Android TV, and Swiftfin, and iOS is marked
  unsupported ([Jellyfin codec support](https://jellyfin.org/docs/general/clients/codec-support/)).
  These are client categories, not a guarantee for every device in each group.
- HDR support is more limited. Jellyfin says newer iOS hardware can support AV1
  where the client codec supports it; macOS Chrome supports HDR10 on HEVC, VP9,
  and AV1, while Firefox supports HDR on VP9 and AV1. Android and Android TV
  depend on the particular device and source format ([Jellyfin HDR support](https://jellyfin.org/docs/general/clients/codec-support/#hdr-support)).
  It also says that server-side transcoding from HDR requires HDR-to-SDR tone
  mapping because it does not support HDR-to-HDR tone-mapping or HDR metadata
  passthrough ([Jellyfin transcoding](https://jellyfin.org/docs/general/post-install/transcoding/#hdr-to-sdr-tone-mapping)).
  Do not infer Dolby Vision preservation from a successful AV1 video encode;
  validate the profile and playback on every target client.
- Retaining all streams is configurable but still needs verification. FileFlows'
  FFmpeg Builder says unmodified streams, including subtitles, are copied by
  default ([FileFlows FFmpeg Builder](https://fileflows.com/docs/plugins/video-nodes/ffmpeg-builder/)).
  Container support, image subtitle rendering, default/forced flags, chapters,
  attachments, HDR colour metadata, and Dolby Vision metadata remain acceptance
  criteria for a sample conversion.

### Hardware feasibility

| Hardware path | Primary-source capability | Decision use |
| --- | --- | --- |
| Intel Quick Sync / Arc | Intel documents fixed-function media decode, encode, and processing independent of GPU compute, and says Arc A-series and Intel Server GPU add AV1 encode ([Intel](https://www.intel.com/content/www/us/en/docs/oneapi/optimization-guide-gpu/2024-2/media-engine-hardware.html)). | Viable when the exact iGPU or Arc GPU exposes AV1 encode through the installed Linux driver and FFmpeg build. Confirm it on the worker; generation names alone are insufficient. |
| NVIDIA NVENC/NVDEC | NVIDIA documents separate NVENC/NVDEC engines, AV1 encode/decode support, and a GPU-specific support matrix ([NVIDIA Video Codec SDK](https://developer.nvidia.com/video-codec-sdk)). | Viable on a GPU whose matrix row has the required AV1 encode and decode profiles. The SDK's Blackwell quality and throughput statement is not a result for earlier generations. |
| AMD VCN / Radeon | AMD documents full H.264, HEVC, and AV1 encode/decode for RX 7900 series ([AMD Radeon for Creators](https://www.amd.com/en/products/graphics/radeon-for-creators/video-editing.html)) and model-specific AV1 columns in its [graphics specification database](https://www.amd.com/en/products/specifications/graphics.html). | Viable for the exact supported GPU and software path. Check the model rather than assuming all Radeon or Ryzen graphics can encode AV1. |

Jellyfin can use hardware acceleration for on-the-fly video transcoding when
the available hardware supports it ([Jellyfin hardware acceleration](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/)).
That does not prove the same device supports *offline AV1 encode*, so probe the
selected FFmpeg encoder and perform a measured test. Hardware encode improves
throughput and power behavior, while software encoding permits different
quality-speed choices; neither source supports treating hardware output as
visually equivalent to a software encode at identical settings.

### Automation candidates

| Tool | Documented fit | Constraint for this decision |
| --- | --- | --- |
| Tdarr | Flows can use worker tags to stage a transcode on an unmapped worker and perform filesystem replacement on a mapped worker ([Tdarr nodes](https://docs.tdarr.io/docs/nodes/nodes/)); the replace plugin replaces the original working file ([Tdarr Replace Original File](https://docs.tdarr.io/docs/plugins/flow-plugins/index/file/Replace%20Original%20File/)). | Use a separate output or verified backup phase during the pilot. Replacement removes the working source unless another link or backup remains. Limit concurrency and require codec, resolution, HDR/DV, and size guards before replacement. |
| FileFlows | Libraries scan directories, choose a flow, filter video codecs/resolution/duration, and can skip already processed files ([FileFlows libraries](https://fileflows.com/docs/webconsole/libraries/)). Its FFmpeg builder retains unchanged streams by default. | Suits a guarded library workflow, including separate input/output locations. Its `Replace Original` option removes the original, so do not enable it until the policy has passed a representative pilot ([FileFlows library output](https://fileflows.com/docs/webconsole/libraries/library)). |
| Direct FFmpeg queue | FFmpeg provides the available software-wrapper controls and can list the installed encoders; it has no policy layer for library scanning, result approval, or source retention ([FFmpeg codecs](https://ffmpeg.org/ffmpeg-codecs.html)). | Best when configuration management already provides queueing, logs, free-space checks, retry policy, and an immutable source path. Otherwise use one of the workflow tools above. |

## Validation and limits

Repository inspection found an RTX 4070 selected for the desktop display and
NVENC, and Jellyfin configured for NVENC, AV1 decode, and AV1 output
([desktop GPU configuration](../../hosts/nixos/desktop/local/hardware/graphics.nix),
[Jellyfin configuration](../../hosts/nixos/desktop/local/homelab/media.nix)).
Read-only probes found NVIDIA driver 595.99.02 and the FFmpeg encoders
`av1_nvenc`, `libsvtav1`, and `libaom-av1`. That makes an NVENC pilot feasible
in principle. No encode test ran, so this is not a throughput, quality, or
metadata-preservation result for the selected settings.

The same inspection found that Sonarr and Radarr import with hardlinks, and
that the download and library trees share a Btrfs filesystem
([hardlink setting](../../hosts/nixos/desktop/local/homelab/media.nix),
[storage setting](../../hosts/nixos/desktop/local/homelab/default.nix)). qBittorrent is
configured to stop at download completion ([qBittorrent setting](../../hosts/nixos/desktop/local/homelab/media.nix)).
This makes in-place replacement particularly unsuitable for the first rollout:
the pilot must write a separate output and record inode and link-count changes
before and after each operation. Re-encoding a library hardlink does not reclaim
the source file's blocks while the corresponding download link remains; the
pilot also needs free capacity for both files. This is an inference from the
repository configuration, not a claim about *arr or Btrfs internals.

The configured quality policy includes 1080p and 2160p selections, with 2160p
requests expected to use HDR where a suitable source exists
([quality-profile integration](../../hosts/nixos/desktop/local/homelab/media.nix)).
There is currently no populated media-library directory, so no representative
media benchmark, client playback test, or automation installation was run.
Claims above are primary documentation retrieved on 2026-09-24; vendor
capability is conditional on the exact device, driver, and FFmpeg build.

Before enabling replacement, validate a pilot containing SDR and HDR10 material,
Dolby Vision profiles in use, common audio codecs, text and image subtitles,
chapters, and target resolutions. For each file: compare duration and stream
maps/metadata, inspect visual quality at difficult scenes, measure output size
and encoding time/energy, and verify Direct Play plus subtitle and audio
selection on every active Jellyfin client. Record whether a server transcode,
tone-map, remux, or subtitle burn-in occurred. A client can change its codec
support after an app or operating-system update, so repeat playback checks when
the client set changes.

The implementation gates are:

1. Probe FFmpeg for the planned NVENC AV1 encoder and run a single copy-only
   encode; record encoder version, command, elapsed time, and peak resource
   use.
2. Reject an output unless it preserves the intended video dimensions, frame
   rate, duration, chapters, audio streams, subtitle streams and their
   language/default/forced flags. Require the expected HDR metadata and Dolby
   Vision playback where applicable; otherwise keep the source and exclude that
   class from automatic conversion.
3. Reject an output unless it meets a predeclared size threshold and passes
   visual inspection at difficult scenes. Compare against the source at the
   same playback conditions; do not use output size alone as a quality signal.
4. Require Direct Play with audio and subtitles on each active client. Treat a
   remux, video transcode, tone-map, or subtitle burn-in as a failed result for
   that client/profile until an explicit exception is accepted.
5. Confirm that the copy-only workflow leaves every source inode and hardlink
   count intact, qBittorrent completion state unchanged, and Sonarr/Radarr
   library and release history unchanged. Select source files that are no longer
   needed as torrent payloads before testing any space-reclaiming promotion.
   Test one controlled promotion and rollback before enabling replacement.

## Implication for this repository

Use a selective NVENC copy-only pilot. First select releases whose source files
are no longer required as torrent payloads, then queue only a small set of SDR
1080p files and retain every source or a verified backup. Expand to HDR10 and
Dolby Vision only after their metadata and client playback gates pass. Do not
add an always-on replacement workflow until the pilot shows enough measured
storage or bandwidth benefit and the hardlink and *arr-state gates pass.

If the pilot succeeds, put a single-worker queue behind a NixOS systemd service
and timer or an Arr import notification. The worker should wait for a completed
import, check codec and free space, transcode to a separate path on the same
filesystem, verify the output, then promote one file with a rollback copy and
ask the owning Arr app and Jellyfin to rescan it. It must never write into the
download payload or follow a hardlink for in-place modification. A separate
output is the starting point even if Tdarr or FileFlows supplies the queue.
