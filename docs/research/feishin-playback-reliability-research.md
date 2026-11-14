# Feishin playback reliability on macOS

> Historical snapshot: personal package recipes referenced here have since been retired or renamed. These audit findings describe the cited source, not the current package selection.

Reviewed: 2026-10-08. Scope: Feishin 1.17.0, its pinned Node-MPV fork,
and the managed Darwin package.

## Finding

Audio-device discovery and player initialization can start separate mpv children
using the same IPC socket. The temporary device probe then removes that socket
and invalidates playback events while the playback child remains alive. This
explains a client that reports an initialized player but fails to load tracks or
update playback state.

The [main player device handler](https://github.com/jeffvli/feishin/blob/v1.17.0/src/main/features/core/player/index.ts#L694-L758)
waits for an existing initialization promise, but does not register its own
creation as that promise. Discovery can therefore start first and overlap a
later initialization. Both use the process-wide socket. Temporary cleanup also
changes the global playback-event generation.

The [audio-device hook](https://github.com/jeffvli/feishin/blob/v1.17.0/src/renderer/features/settings/components/playback/audio-settings.tsx#L59-L101)
runs after renderer initialization. The ordinary
[volume control](https://github.com/jeffvli/feishin/blob/v1.17.0/src/renderer/features/player/components/right-controls.tsx#L542-L559)
uses this hook, so the race does not require opening Settings.

The existing managed package serialized initialization and restart. Device
discovery and player quit were outside that lock. Quit could also clear the
replacement player after a concurrent initialization.

## Correction

The [managed lifecycle patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/fe/feishin-managed/mpv_lifecycle.py)
serializes device discovery and player quit with initialization and restart.
Temporary cleanup completes before a playback child can reuse the socket.
Device queries have a three-second timeout and clear their timer afterward.
Quit uses the existing bounded shutdown directly, without awaiting a separate
unbounded stop command.

This timeout matters because the pinned
[Node-MPV IPC implementation](https://github.com/jeffvli/Node-MPV/blob/32b4d64395289ad710c41d481d2707a7acfc228f/lib/ipcInterface/ipcRequest.js)
has no per-command timeout. An indefinitely pending device query must not prevent
later restart or shutdown from acquiring the lifecycle lock.

## Validation

A live native reproduction called `quit()`, waited for shutdown, then requested
`getAudioDevices()` and `initialize({})` concurrently through Feishin's exposed
player API. Before the correction, both calls completed and `isRunning()`
returned true, but the playback socket was absent. The original child from the
reported broken session also remained alive after its parent exited.

After the correction, three repetitions preserved the socket and completed
initialization in 486–629 ms. An authenticated lossless server stream reached
an advancing playhead through Feishin's actual playback API in 1.125 seconds.
The probe muted playback and stopped afterward. Three direct stream probes
received their first 64 KiB in 0.212–1.180 seconds. These measurements distinguish
the confirmed client race from server availability; they do not rule out
intermittent network delays.

The [regression tests](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/fe/feishin-managed/mpv-lifecycle.test.mts)
execute the packaged main-process handlers with controlled child-process timing.
The original socket and quit races failed before the correction. Seven cases
cover both initialization/discovery orders, restart, quit, playback events,
and recovery from stalled commands. The package runs these tests when applying
the Darwin patch. Native runtime checks supplement the simulated IPC tests.

The corrected installed archive was tested on macOS and its application
signature was verified. A complete native Nix rebuild did not finish because
existing garbage collection held the store. Native archive and runtime checks
verify the installed correction; the package derivation remains unverified.
