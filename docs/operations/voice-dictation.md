# Free offline voice dictation

Both platforms select Handy with **Parakeet Unified EN 0.6B, Q8_0 GGUF** for
responsive English dictation. The native GGUF backend supports Metal on Apple
Silicon and Vulkan on Linux. Automatic selection prefers a discrete GPU over
integrated graphics, then falls back to CPU when necessary; on the desktop the
intended GPU is the RTX 4070, with the small CPU-integrated GPU a fallback.
See the [hardware and model research](../research/voice-dictation-models-research.md)
for the source evidence and limits.

Weights stay loaded for five idle minutes, avoiding repeated cold loads during
a dictation session. This retains model memory between recordings; the microphone
is still opened only for dictation. No API key, subscription, cloud transcription,
or separate cleanup model is used. The earlier Cohere ONNX selection favored
batch accuracy; it is superseded by this speed/accuracy choice.

## Use

One service per machine handles Zen, T3 Code, and other applications. There is
no browser extension, Zen-specific recording command, or second Whisper model
to configure. Use the system-wide shortcut rather than a browser or T3 microphone
button, which may invoke another transcription path.

Focus the T3 Code composer or another text field, then hold the shortcut while speaking. Release either key to finish:

| Platform | Hold to record; release to finish | Cancel |
| --- | --- | --- |
| Linux | Left Alt+Space | Overlay cancel button |
| macOS | Left Option+Space | Ctrl+Option+Shift+D |

For a Zen search, press **Ctrl+L** on Linux or **Command+L** on macOS first, then
start dictation. The same shortcut works in web forms and T3's composer. Finish
dictation, review the text, then press Enter when ready. Starting dictation does
not change application focus.

Finished text is pasted for review. Dictation does not press Send. On Linux,
Handy's bottom recording overlay provides recording and transcription feedback
and a cancel control. Open Handy for model management, microphone selection,
and vocabulary. The live overlay shows provisional streaming text while you
speak; release finalizes and pastes it for review. Unified buffers context before
its first preview, so expect a short initial delay rather than immediate text.

On macOS, open **Handy** from the managed Applications directory. Complete its
permission prompts and enable Handy under **System Settings → Privacy & Security
→ Microphone** and **Accessibility**. These grants belong to macOS and require
the user's approval. The selected model is already installed. Keep the microphone
set to the intended device; choose a wired or built-in mic if Bluetooth headset
capture is unclear. Handy's custom vocabulary remains editable in its UI.

The configuration is in [the dictation module](../../modules/home/desktop/dictation.nix).
Handy's native `handy_keys` backend owns side-specific shortcuts and actual
press/release events on both platforms; `shortcut_activation` is `push_to_talk`.
The native user service starts the app at login; in-app autostart is off.
On Linux, keyboard evdev access and uinput are required to consume the chord
without inserting a space. The desktop's `70-handy-input.rules` grants access
through logind ACLs to the active local seat, restricted to keyboard event
devices and uinput. This gives the active account keyboard-read and input-injection
capability; it does not add permanent `input` group membership. Handy's blocking
backend grabs keyboards and forwards unrelated keys through virtual devices.
Stop Handy if keyboard forwarding misbehaves; avoid another blocking evdev listener.
The udev rules must run before `73-seat-late.rules`; after activation, reconnect
keyboards or trigger the affected udev devices before restarting Handy if access
has not yet refreshed. The Linux launcher uses native Wayland and GTK layer shell
for a non-focusable overlay.
The old native Fn/Globe dictation assignment is reset; macOS may need a restart
before that key stops opening native Dictation.

## Model updates and cleanup

The model is supplied by `pkgs.parakeet-unified-en-gguf` from nixpkgs-personal.
Its [package-local updater](../../pkgs/pkgs/by-name/pa/parakeet-unified-en-gguf/README.md)
is discovered by the existing daily package-update workflow. It generates the
immutable revision and verified hash; the home module owns no duplicate pin.
The managed model has a distinct `nix-` filename and local model ID so Handy's
Hugging Face cache cannot take precedence over the selected package. Existing
shared caches remain untouched. Model updates arrive with normal package/input
updates and deployment, and Nix
rollback restores the previous generation. Changing model families or Q8
quantization remains an explicit package choice. There is no runtime update job
competing with recording or inference.

Native filler removal is explicitly enabled. Handy also retains its built-in
whitespace and repeated-word cleanup, while the vocabulary and custom filler
list remain editable in Handy. Keep the vocabulary small and review fuzzy
substitutions, especially for technical terms. Do not add ordinary words such as
“like” to the filler list. AI postprocessing stays disabled, so cleanup does not
load a second model or contact a provider. These string operations have expected
small overhead; target-platform latency has not been measured.

## Health and validation

On Linux, inspect `systemctl --user status handy` and restart it with
`systemctl --user restart handy`. On macOS, inspect
`launchctl print gui/$(id -u)/com.pais.handy.service`. Open the Handy app to inspect
microphone selection and permission status.

Historical validation on 2026-11-08 used the previous Parakeet model and
shortcuts. It included configuration reconciliation tests, isolated
Home Manager builds, and native transcription of the public whisper.cpp JFK
sample. This checks a working recognizer, not accuracy on technical prompts or a
live end-to-end paste into T3. The temporary macOS signing repair seals Handy's
source-built bundle after packaging; it is ad-hoc signed, not vendor notarized.
Apple's strict deep signature verification passes for the installed bundle.

Validation on 2026-11-17 passed full Linux and Darwin system derivation
evaluation, the Linux model/preparation package build, pinned Nix and Python
static checks, udev rule verification, and a focused Gitleaks scan. No full system
build, activation, native Darwin build, or live dictation check ran.

The package-managed follow-up passes the package repository's checks and both
profiles' model-metadata evaluation on Linux. The model package builds and the
native updater verifies upstream content. Complete host validation and native
macOS build/activation remain separate from those focused checks.

The model and input changes still require live-session checks: hold
and release either key (including releasing Alt/Option first), right-side modifier
exclusion, cancellation, keyboard hotplug, and pasting into an unsent draft on
both platforms. Source research and configuration evaluation do not establish
microphone quality, recognition latency, keyboard forwarding, or focus/paste
behavior. No desktop activation is implied by a successful build.

Sources: [Handy](https://github.com/cjpais/Handy),
[Cohere catalog and pinned checksum](https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/managers/model.rs).

For acceleration diagnostics, run `handy --list-devices`; launch Handy's settings
to inspect the selected backend. The configuration uses automatic device selection,
not a persistent numerical index that can change across boots. On macOS Metal
uses unified memory; the desktop's discrete GPU uses its own VRAM. The integrated
GPU is not assumed faster than the desktop CPU for short utterances. Upstream
benchmarks on other machines do not predict either workstation's latency.
