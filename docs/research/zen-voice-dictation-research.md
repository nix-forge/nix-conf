# Zen Browser voice-dictation research

Reviewed: 2026-09-22. Scope: practical text dictation into Zen Browser on the
NixOS desktop (Wayland/Hyprland), with the macOS profile considered where it
changes the choice. This note assesses upstream documentation and the pinned
Nixpkgs source; it does not install, configure, or benchmark a dictation tool.

## Answer

Use **desktop-level local speech-to-text** for Zen on Linux, rather
than waiting for a native Zen/Firefox feature or making an extension the primary
solution. The best current feature fit is
[hyprwhspr v1.45.2](https://github.com/goodroot/hyprwhspr/releases/tag/v1.45.2):
it supports Hyprland bindings, PipeWire-compatible microphone selection,
clipboard paste or Wayland direct typing, and local Whisper, faster-whisper,
Vulkan, NVIDIA, and ONNX-ASR backends. Keep it local-only, select a model that
fits the hardware, paste rather than synthetic typing, and bind start/stop in
Hyprland. That keeps audio out of third-party transcription services and works
in Zen, other browsers, terminals, and native applications.

It is not yet a direct package in the repository's pinned Nixpkgs. A future
declarative integration should package and pin it first; do not adopt its
upstream `curl | bash` installer in configuration. If a fully Nixpkgs-packaged
solution is required now, trial
[Voxtype 1.0.1](https://github.com/peteonrails/voxtype/releases/tag/v1.0.1)
with its local Whisper or Parakeet backend. The pinned package describes it as
Wayland push-to-talk dictation and includes the Wayland injection dependencies.
This is an inference from its package and upstream feature set, not a local
quality or latency result.

On macOS, native Dictation offers the smallest integration and enters text in
Zen's address bar. Apple's on-device claim excludes search boxes, so a Zen
question may leave the Mac. See the [macOS decision and setup note](zen-dictation-macos-research.md)
before choosing it for sensitive questions.

## Findings and sources

### Zen and Firefox do not provide the required native desktop path

Mozilla labels `SpeechRecognition` as limited availability. Current Firefox
compatibility data marks desktop support as preview; Gecko's preference defaults
`media.webspeech.recognition.enable` to false, and Firefox source documentation
describes its new local implementation as macOS-only. This site-facing API is
also not a system-wide text-entry facility. Zen is Firefox-derived, but no Zen
source in the reviewed material documents an independent native dictation
service. Therefore, treating a website microphone button, experimental Web
Speech API support, or a browser extension as reliable general Zen dictation
would be an unsupported inference.

- [MDN `SpeechRecognition` reference and compatibility status](https://developer.mozilla.org/en-US/docs/Web/API/SpeechRecognition)
- [Firefox browser-compatibility data for `SpeechRecognition`](https://github.com/mdn/browser-compat-data/blob/main/api/SpeechRecognition.json)
- [Gecko default preference for speech recognition](https://github.com/mozilla/gecko-dev/blob/master/modules/libpref/init/StaticPrefList.yaml)
- [Firefox source documentation for Speech Recognition](https://firefox-source-docs.mozilla.org/media/SpeechRecognition.html)

### Preferred Linux option: hyprwhspr with a local backend

hyprwhspr's own documentation specifies Wayland and Hyprland support, `wl-clipboard`
and `wtype` for Wayland, configurable Hyprland bindings, and a user service.
Its configuration schema exposes local `pywhispercpp`, CPU, NVIDIA, Vulkan,
AMD, ONNX-ASR, and faster-whisper backends alongside explicitly remote REST and
WebSocket backends. It defaults to clipboard-plus-paste injection; direct
`wtype` and `ydotool` modes are opt-in. The schema also makes the cost and
privacy choices visible: a model can stay loaded, the microphone can stay open,
and long-form mode saves audio segments temporarily. All three should remain
off unless their latency or recovery benefit is measured and wanted.

The local-only conclusion applies only when a local backend is selected and no
post-transcription hook sends text elsewhere. A remote endpoint, WebSocket,
cloud transcription provider, or cleanup hook changes the data boundary. The
upstream configuration accepts environment-variable substitution for API
credentials, which is useful operationally but is not an argument to place a
credential in a public Nix file.

- [hyprwhspr README: platform, Wayland, backends, and service setup](https://github.com/goodroot/hyprwhspr/blob/v1.45.2/README.md)
- [hyprwhspr configuration: recording, Hyprland bindings, and backends](https://github.com/goodroot/hyprwhspr/blob/v1.45.2/docs/CONFIGURATION.md)
- [hyprwhspr configuration schema: injection, resource, and remote-endpoint controls](https://github.com/goodroot/hyprwhspr/blob/v1.45.2/share/config.schema.json)

### A small, transparent fallback: nerd-dictation

[nerd-dictation](https://github.com/ideasman42/nerd-dictation) remains a viable
offline fallback where a small Vosk model, a manual begin/end shortcut, and
simple text transformations are sufficient. Its upstream documentation calls it
a single Python script with no background process and supports PipeWire capture
through `pw-cat`; it can inject with `wtype`, `dotool`, or `ydotool` on Wayland.
It is less suitable as the default recommendation for high-quality free-form
dictation: the project last changed on 2025-10-10, and the reviewed README
documents Vosk rather than the newer Whisper/Parakeet backends offered by the
other candidates. That is a maintenance and feature-scope observation, not a
measured accuracy comparison.

`ydotool` and other virtual-input helpers have broad power: their purpose is to
send input outside the dictation application. Prefer clipboard paste into the
focused Zen field, use an explicit press-to-talk binding, and restrict any
device or keyboard access to the smallest workable scope. Treat a transcript in
the clipboard as sensitive until it is cleared or replaced.

- [nerd-dictation README: architecture, PipeWire, and Wayland output methods](https://github.com/ideasman42/nerd-dictation/blob/41f372789c640e01bb6650339a78312661530843/readme.rst)
- [nerd-dictation's documented ydotool integration](https://github.com/ideasman42/nerd-dictation/blob/41f372789c640e01bb6650339a78312661530843/readme-ydotool.rst)

### Whisper.cpp is the portable local engine, not a complete dictation UX

[whisper.cpp v1.9.4](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.9.4)
is a C/C++ implementation with CPU, Vulkan, CUDA, ROCm, Metal, and Core ML
paths. Its upstream model table gives an approximate working-memory range from
388 MiB for `base` to 3.9 GiB for `large`; quantization can reduce model storage
and memory use. This makes it a strong local engine for a service or a custom
Hyprland script, but it does not by itself bind a hotkey, record PipeWire audio,
or place text in Zen.

Use `base` or `small` as the first latency/resource experiment, then compare a
larger model only with representative speech. Model quality, GPU driver support,
microphone processing, language, and punctuation determine the actual result;
the source does not establish a universally best model.

- [whisper.cpp v1.9.4 README: supported accelerators, platforms, and model memory table](https://github.com/ggml-org/whisper.cpp/blob/v1.9.4/README.md)

### Browser extensions are optional, browser-scoped experiments

The open-source [Speech Recognition Polyfill Firefox extension](https://addons.mozilla.org/en-US/firefox/addon/speech-recognition-polyfill/)
can supply local Vosk, Whisper, or NVIDIA Parakeet providers and polyfill Web
Speech sites. Its source documents an all-sites content-script permission so it
can patch pages, and the AMO listing says locally downloaded models do not
survive browser shutdown because of Firefox limitations. It can be useful for
one site that specifically expects Web Speech, but it does not deliver a
system-wide activation flow, incurs browser-lifetime model downloads, and has a
larger browser permission surface than a focused desktop service. It should not
be force-installed or given a cloud provider by default.

Review the exact extension version, requested permissions, network provider,
and model source before enabling it. A local model choice does not make an
extension's page access harmless; an all-sites content script can read or alter
the pages to which it is injected.

- [Speech Recognition Polyfill source: providers, permissions, and Firefox behavior](https://github.com/apersongithub/Speech-Recognition-Polyfill)
- [AMO listing for the reviewed extension](https://addons.mozilla.org/en-US/firefox/addon/speech-recognition-polyfill/)

### Nix packaging and repository fit

The repository's pinned Nixpkgs revision is `c5c4a43b0e8056328ec4529f735cabdb8f1942bb`.
Evaluation of that exact input on 2026-09-22 found:

| Candidate | Availability in pinned Nixpkgs | Reviewed package version | Relevant integration fact |
| --- | --- | --- | --- |
| `whisper-cpp` / `whisper-cpp-vulkan` | Yes | 1.9.2 | The derivation exposes optional CUDA, ROCm, Vulkan, Metal, and Core ML builds. |
| `voxtype` | Yes | 1.0.1 | The derivation supplies Wayland runtime tools and supports optional Vulkan and ONNX engines. |
| `hyprwhspr-rs` | Yes, but separate project | 0.3.33 | This is `better-slop/hyprwhspr-rs`, not goodroot/hyprwhspr. |
| goodroot `hyprwhspr` | No | upstream 1.45.2 | Requires a new pinned package definition before declarative use. |
| `nerd-dictation` | No | upstream main commit above | Requires packaging or an external, pinned source. |

The stable packaged `whisper-cpp` is behind the upstream v1.9.4 release, so a
future pin should deliberately choose the repository input's version or update
it; it must not claim to be the latest upstream version. The existing optional
`cli-whisper` module uses Python `openai-whisper` with a CPU-only Torch override
to avoid a large CUDA runtime, which supports keeping any desktop dictation
feature separately selected and hardware-specific.

- [Pinned Nixpkgs `whisper-cpp` derivation](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/by-name/wh/whisper-cpp/package.nix)
- [Pinned Nixpkgs `hyprwhspr-rs` derivation](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/by-name/hy/hyprwhspr-rs/package.nix)
- [Pinned Nixpkgs `voxtype` derivation](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/by-name/vo/voxtype/package.nix)
- [Existing CPU-only Whisper choice](../../modules/home/cli/whisper.nix)

### macOS

Apple documents macOS Dictation as text entry "anywhere you can type," with a
customizable shortcut, selectable microphone and language, and continued typing
on Apple silicon. Apple's on-device statement covers general text but excludes
search boxes, so the privacy of Zen address-bar questions cannot be inferred
from the Keyboard status. The optional Improve Siri & Dictation program permits
Apple to store and review samples; declining it does not guarantee local search
dictation. See the [dedicated macOS note](zen-dictation-macos-research.md).

whisper.cpp is also portable to macOS and its source lists Apple Silicon,
Metal, and Core ML support. It is an alternative only when an independently
managed local engine is worth more than macOS's integrated text entry; this
research did not test a Nix Darwin build, microphone permission flow, or Zen
focus behavior for it.

- [Apple: Dictate messages and documents on Mac](https://support.apple.com/en-sa/guide/mac-help/mh40584)
- [Apple: Improve Siri & Dictation data sharing](https://support.apple.com/en-au/127070)

## Validation and limits

This research retrieved the linked primary project sources and release metadata
on 2026-09-22. It evaluated the repository's pinned Nixpkgs attribute presence
and versions for `x86_64-linux`; no packages were built, services activated,
microphones accessed, browser extensions installed, or latency/accuracy tests
run. The note therefore establishes availability and documented capabilities,
not speech-recognition quality, real-time latency, security isolation, or
successful focus/paste behavior on this desktop.

The implementation follow-up on the same date built the generated `zen-dictate`
command and its pinned model on the desktop. A one-second synthetic-silence
probe confirmed that pinned `whisper-cli` accepts the model and command flags
and writes its text output file. Five isolated command tests passed for normal
delivery, changed-window rejection, cancellation, second-press completion, and
the wall-clock recording limit; the desktop system build, ShellCheck, Bash
syntax, Ruff, and Nix formatting checks passed. This does not
exercise the real microphone, Hyprland shortcut, notification display, or
Zen address bar. Those still need a live-session check after activation.

Upstream release and package versions age quickly. Before implementation, repeat
the focused package evaluation, inspect the exact source and dependency closure,
and test press-to-talk, cancellation, clipboard clearing, non-ASCII text,
password fields, Zen textareas, and a terminal in an isolated profile.

## Implication for this repository

For the requested Zen search workflow, the Linux implementation is a smaller
local-only command in [the Zen dictation module](../../modules/home/browsers/zen/dictation.nix).
It uses the pinned Nixpkgs `whisper-cpp` package, a
[pinned `small.en-q5_1` model](https://huggingface.co/ggerganov/whisper.cpp/blob/c521a4b02f422512d734391fdf08bb08c0862f68/ggml-small.en-q5_1.bin),
PipeWire capture, and either an editable review dialog followed by Zen's search
command or `wtype` on Hyprland to put text directly in Zen's address bar. This
avoids a resident model, third-party transcription endpoint, browser-wide
extension permission, and clipboard history. It is limited to English and
Zen's address bar; the best current general-purpose option remains hyprwhspr
once it has a reviewed, pinned package. The selected model is a reasoned
starting point, not a measured accuracy winner. Measure `base` and `small`
with representative speech before tuning GPU acceleration or model size.

In the Hyprland delivery mode, the search remains unsubmitted so the user can
correct errors. In the portable Linux mode, the user edits the question in a
review dialog and confirms before Zen searches. Recording has a
60-second limit, and audio and transcript files are removed from the private
session runtime directory after each run. The command compares the focused Zen
window before typing to reduce wrong-window entry risk. These choices are
visible in [the command source](../../modules/home/browsers/zen/scripts/zen-dictate-linux.sh.in).
On the selected desktop profile, focus Zen and press `Super+Alt+D` to start,
press it again to finish, or press `Super+Alt+Shift+D` to cancel. Review the
question in Zen's address bar and press Enter to search.
Other Linux profiles can select `browsers-zen-dictation` and enable
`programs.zenSearchDictation.enable` without Hyprland. The default
`review-dialog` delivery works on graphical Linux desktops; bind
`zen-dictate toggle` and `zen-dictate cancel` through that desktop's shortcut
settings if desired.
The Darwin profile assigns Fn/Globe to native Dictation through an opt-in
[system module](../../modules/darwin/dictation.nix). The user must still enable
Dictation and choose its privacy settings in System Settings.
