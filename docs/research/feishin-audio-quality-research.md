# Feishin audio fidelity on a shared Linux desktop

Reviewed: 2026-10-13. Scope: Feishin 1.17.0 at `5c169aca8d550032c9aa6e8e2b9f624d03d42fec`, mpv 0.41.0, Navidrome 0.64.2 at `101145742f4762164202cb4858c9126258bdc463`, and a PipeWire desktop using a 48 kHz hardware clock.

## Answer

Use Feishin's mpv backend, request the original server file explicitly, and disable unwanted dynamics processing. For a desktop that also handles games and calls, retain shared PipeWire output. Preserve the existing hardware clock policy and perform any necessary conversion once with a verified high-quality resampler. This avoids lossy server re-encoding and unwanted audio processing; it does not establish bit-perfect playback at every source rate.

## Findings and sources

### Original streams require an explicit request

Feishin's mpv engine calls `getSongUrl` with browser compatibility transcoding skipped. However, when `transcode.enabled` is false, the Subsonic controller returns a legacy stream URL without a format parameter. Navidrome's controller delegates to that implementation. Disabling the Feishin toggle therefore does not guarantee that server-side player defaults will leave audio unchanged. Sources: [Feishin stream controller](https://github.com/jeffvli/feishin/blob/5c169aca8d550032c9aa6e8e2b9f624d03d42fec/src/renderer/api/subsonic/subsonic-controller.ts), [Navidrome delegation](https://github.com/jeffvli/feishin/blob/5c169aca8d550032c9aa6e8e2b9f624d03d42fec/src/renderer/api/navidrome/navidrome-controller.ts), and [mpv engine](https://github.com/jeffvli/feishin/blob/5c169aca8d550032c9aa6e8e2b9f624d03d42fec/src/renderer/features/player/audio-player/engine/mpv-player-engine.tsx).

The controller appends the supplied format and bitrate when its transcoding switch is enabled. The configuration `transcode = { enabled: true, format: "raw", bitrate: 0 }` therefore explicitly requests original bytes, despite the toggle's label. A small upstream integration fix could instead attach `format=raw` when the mpv path disables transcoding. The first option uses existing preferences and avoids a package patch. Changing settings may take effect on a subsequent track because Feishin retains the current resolved URL. Source: [Feishin URL reuse](https://github.com/jeffvli/feishin/blob/5c169aca8d550032c9aa6e8e2b9f624d03d42fec/src/renderer/features/player/audio-player/hooks/use-stream-url.tsx).

OpenSubsonic defines `format=raw` as disabling transcoding and bitrate zero as unlimited. Navidrome 0.64.2 checks raw before applying player bitrate or forced-format overrides; its streamer opens the original media file for that request. Sources: [OpenSubsonic stream endpoint](https://opensubsonic.netlify.app/docs/endpoints/stream/), [Navidrome legacy resolver](https://github.com/navidrome/navidrome/blob/101145742f4762164202cb4858c9126258bdc463/core/stream/legacy_client.go#L59-L90), and [raw file handling](https://github.com/navidrome/navidrome/blob/101145742f4762164202cb4858c9126258bdc463/core/stream/media_streamer.go#L63-L101).

### Reliable native playback

The mpv backend also needs correct child-process ownership. In Feishin 1.17.0, device discovery can create a temporary player concurrently with playback initialization. Both use the process-wide socket; temporary cleanup can unlink it and advance the global event generation, causing the persistent player's progress events to be dropped. This code is shared by Linux and macOS. A query made after a healthy player is running can reuse it safely, so the failure is a startup/restart race rather than an inevitable outcome of every query. Sources: [main player ownership and progress handling](https://github.com/jeffvli/feishin/blob/5c169aca8d550032c9aa6e8e2b9f624d03d42fec/src/main/features/core/player/index.ts) and the [existing native reproduction](feishin-playback-reliability-research.md).

The volume control uses the device-discovery hook, so this can affect ordinary startup. The managed package's existing correction previously ran only on Darwin. Apply the same lifecycle serialization to Linux, install its readiness and message helpers on both platforms, and run the existing regression tests against each patched bundle. Sources: [volume control](https://github.com/jeffvli/feishin/blob/5c169aca8d550032c9aa6e8e2b9f624d03d42fec/src/renderer/features/player/components/right-controls.tsx), [lifecycle correction](../../pkgs/pkgs/by-name/fe/feishin-managed/mpv_lifecycle.py), and [regression suite](../../pkgs/pkgs/by-name/fe/feishin-managed/mpv-lifecycle.test.mts).

### Audio processing and output

Feishin disables user mpv configuration and automatic scripts, so ordinary `mpv.conf` settings do not govern playback. App-specific extra parameters are supported. Source: [Feishin mpv startup](https://github.com/jeffvli/feishin/blob/5c169aca8d550032c9aa6e8e2b9f624d03d42fec/src/main/features/core/player/index.ts).

Keep equalizer and compressor disabled unless deliberately chosen. Their filters change gain, frequency response, or dynamics. Feishin defaults both to disabled and ReplayGain to off, but defaults `replayGainClip` to true. That flag permits clipping when ReplayGain is enabled. Set it false as a guard against a later change. Sources: [filter builder](https://github.com/jeffvli/feishin/blob/5c169aca8d550032c9aa6e8e2b9f624d03d42fec/src/renderer/features/settings/components/playback/mpv-audio-filters.ts) and [default playback settings](https://github.com/jeffvli/feishin/blob/5c169aca8d550032c9aa6e8e2b9f624d03d42fec/src/renderer/store/settings.store.ts).

mpv volume 100 is unity gain. Exclusive output can prevent other applications from using audio; keep it off for a shared desktop. `gapless-audio=weak` permits output changes between unlike tracks. `audio-samplerate=48000` explicitly converts differing rates in mpv. Its resampler options do not affect conversions performed later by PipeWire. Source: [mpv 0.41.0 options](https://github.com/mpv-player/mpv/blob/v0.41.0/DOCS/man/options.rst).

The app's startup property mapper omits `audio-format`, although its individual setting-change mapper handles it. An explicit `--audio-format=float` extra argument avoids relying on that omission when float output is desired. Source: [Feishin property mapper](https://github.com/jeffvli/feishin/blob/5c169aca8d550032c9aa6e8e2b9f624d03d42fec/src/renderer/features/settings/components/playback/mpv-properties.ts).

For an intentionally fixed 48 kHz graph, `--audio-swresample-o=resampler=soxr,precision=28` is a reasonable candidate after verifying installed FFmpeg support. FFmpeg identifies precision 28 as SoX's Very High Quality, and the resampler must be available in the build. It should accompany the explicit output rate; otherwise PipeWire may perform the rate conversion instead. Source: [FFmpeg resampler reference](https://ffmpeg.org/ffmpeg-resampler.html#Resampler-Options).

## Validation and limits

This research inspected tagged upstream files and existing repository notes. The Linux configuration was then exercised locally; no subjective audibility comparison or sustained performance benchmark was performed. The installed managed package was also inspected because local patches can alter tagged behavior.

Local observations:

- Feishin initially selected the web backend. Its local mpv backend is stored as `playback.type = "local"`, rather than `"mpv"`; the main process also stores `playbackType = "local"`. The [player enum](https://github.com/jeffvli/feishin/blob/5c169aca8d550032c9aa6e8e2b9f624d03d42fec/src/shared/types/types.ts) defines these values.
- The installed package failed before opening its window because its archive omitted `managed-login-renderer.cjs`. Its Darwin helpers similarly omitted `mpv-message.cjs`. The package recipe now copies both dependencies and checks the installed archive, rather than only the compiled helper directory. The initial Linux helper repair built successfully; the package repository's evaluation checks passed on all three supported platforms. The Linux lifecycle extension also built successfully, passed all seven lifecycle regression cases against the patched bundle, and passed installed-archive checks. The final package repository check passed. A muted live test returned 29 audio devices while playback time kept advancing; prior pause, mute, and volume settings were restored. Darwin Electron behavior was not exercised.
- After restarting the corrected application, mpv ran with shared PipeWire output, `format=raw`, unlimited bitrate, speed 1, ReplayGain disabled, clipping permission disabled, and an empty audio-filter list. Both stereo links reached the MOTU headphone sink. The first 64 KiB of an actual raw stream matched the original download bytes.
- A synthetic 44.1 kHz probe and a 24-bit FLAC server probe both decoded successfully through SoXR precision 28 to 48 kHz float. mpv expresses the resampler dictionary as `resampler=soxr,precision=28`; a colon between these entries was rejected during the initial probe and was corrected.
- Live FLAC playback reported a 44.1 kHz source and 48 kHz float output. The MOTU hardware stream reported packed 24-bit PCM at 48 kHz. A roughly 25-second sample measured mpv at about 1.1% of one CPU core, including decoding and resampling. This is a short observation, not a sustained workload benchmark.
- Playback preferences were saved in Feishin's existing persistent settings store. Desktop output volume remained unchanged; existing application attenuation was retained.
- The isolated desktop system build, dry activation, and activation passed. Its closure comparison changed only the managed Feishin package. The normal desktop launcher resolved to the corrected package, and a subsequent app restart retained the original-stream and audio-processing settings.

These observations establish the tested streaming and conversion path. They do not establish bit-perfect playback at differing source rates, improve already-lossy source files, validate every codec, or prove subjective sound quality.

## Implication for this repository

Save the desktop's original-stream and audio-processing preferences in Feishin's supported persistent settings. Repair missing helper dependencies and apply the shared lifecycle correction in the owning package recipe. Keep the dedicated mpv sidecar, shared PipeWire routing, and app identity. Document the fixed-rate conversion honestly. Native-rate playback would require a separate desktop graph and clock decision; it is not achieved by selecting a higher output sample rate in Feishin alone.
