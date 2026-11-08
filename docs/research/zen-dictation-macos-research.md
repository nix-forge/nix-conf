# Zen Browser dictation on macOS

Reviewed: 2026-09-22. Scope: entering a spoken search in Zen's address bar on
the Apple-silicon Darwin profile. This is a source review of macOS Tahoe-era
documentation, the pinned Nix inputs, and upstream releases. The companion
configuration adds the supported Fn/Globe setting; this review did not test a
microphone or Zen session.

## Answer

Use macOS Dictation first if sending address-bar speech to Apple's Dictation
service is acceptable. It is the smallest and least intrusive choice: macOS
owns microphone capture, text insertion, language downloads, and the shortcut,
and Apple says Dictation enters text wherever typing is possible. Focus Zen's
address bar with `Command-L`, invoke Dictation, speak the query, inspect the
result, then submit it manually.

There is one important limit. Apple says its on-device statement applies to
*general text Dictation* and explicitly uses a search box as the example that
is outside that statement. Therefore, no source supports a claim that a Zen
address-bar query remains on the Mac, even when Keyboard settings report that
general Dictation is processed on-device. Do not use native Dictation for this
workflow when fully local transcription is a hard requirement.

The supported declarative part is narrow. Pinned nix-darwin can assign the
Fn/Globe key to `Start Dictation`; it cannot enable Dictation, select a
language or microphone, opt out of sharing, or choose Apple's arbitrary custom
shortcut. Home Manager has no Dictation or Voice Control module. The honest
native setup is a small Nix assignment plus a one-time user action in System
Settings. Do not write guessed `defaults` keys for the remaining controls.

If address-bar transcription must stay local, evaluate Voxtype v1.0.1 as a
separate, pinned macOS application package. Its upstream release has a universal
macOS binary and describes local Whisper and ONNX Parakeet engines. It is the
only reviewed option that combines recording, a global hotkey, local models,
and macOS text output. It also needs Microphone, Input Monitoring, and
Accessibility permission, runs a daemon, and its own macOS notes list ad-hoc
signing and disabled audio feedback. That is a much larger authority and
resource footprint than native Dictation. I would package and trial it only
after the native privacy boundary proves unacceptable. Leave automatic Enter
submission off.

## Findings and sources

### Apple Dictation is convenient, but address-bar locality is undocumented

Apple's current Mac guide says to put the insertion point in the target app and
start Dictation with the Microphone key, the Dictation shortcut, or Edit > Start
Dictation. It says Dictation can enter text anywhere typing is possible and
that on Apple silicon a person can continue typing while dictating. This supports
the Zen flow because the address bar accepts ordinary text input. It does not
establish successful behavior in a live Zen release, which still needs a manual
check.

The same guide says Keyboard settings show whether voice input and transcripts
for general text Dictation are processed on device, then qualifies it with
"for example, composing messages and notes, but not dictating in a search
box." Apple also says an internet connection may be necessary. The secure
interpretation is conservative: an address-bar query may leave the device.
Declining *Improve Siri & Dictation* is still sensible, but it only declines
the optional storage and review of samples. It is not an on-device guarantee
for search boxes.

- [Apple: Dictate messages and documents on Mac](https://support.apple.com/en-qa/guide/mac-help/mh40584/mac)
- [Apple: Keyboard settings on Mac](https://support.apple.com/en-qa/guide/mac-help/-kbdm162/mac)
- [Apple: Improve Siri & Dictation](https://support.apple.com/en-ie/127070)

### Native configuration needs a user-owned step

At the pinned nix-darwin revision `4cff07de74b50e64bdd68cd4e722ab5b6b35ee48`,
the only typed Dictation option is
`system.defaults.hitoolbox.AppleFnUsageType`. It accepts `"Start Dictation"`
and its own description says a restart is needed. The same pinned source has no
other Dictation or Voice Control option. A scan of the pinned Home Manager
revision `4ac5a2ae9025eab1ebece4f9df8c315fd84a738a` found none either. This
repository does not currently set that option.

The Darwin module uses this supported setting:

```nix
system.defaults.hitoolbox.AppleFnUsageType = "Start Dictation";
```

After activation and restart, the user must open **System Settings > Keyboard >
Dictation**, turn it on, choose the language and microphone, select the
Dictation shortcut if Fn/Globe is not desired, and select **Not Now** for
*Improve Siri & Dictation*. The user should then read the on-device/network
status shown below Dictation and treat the address bar as excluded from its
assurance. This is intentional. macOS controls the service state and consent,
and a Nix activation must not pretend it can grant or preserve them.

`macos.preferences.customUserPreferences` exists in this repository as an
escape hatch for untyped preferences. It does not make undocumented Dictation
keys supported, and it cannot safely automate consent. Do not use it here.

- [Pinned nix-darwin `hitoolbox` option](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults/hitoolbox.nix)
- [Repository macOS preference boundary](../../modules/darwin/macos.nix)
- [Repository Apple-silicon profile](../../homes/macbook-pro-m4/default.nix)

### Voice Control is the wrong default for one search field

Voice Control can navigate applications, operate screen items, dictate, and
edit text. It offers Dictation, Spelling, and Command modes, so it can be
useful when someone wants hands-free control of Zen as well as text entry. It
replaces standard Dictation while enabled, listens until paused, and introduces
spoken command recognition where a brief Dictation invocation would suffice.
Apple's cited pages do not give an on-device assurance for Zen's address bar.
There is no pinned Nix option that configures it.

For a search-only workflow, use neither Voice Control nor a custom Voice
Control command as the first choice. It has a broader listening and command
surface without solving the search-box privacy gap. It remains the appropriate
accessibility option if the user actually needs voice navigation.

- [Apple: turn Voice Control on or off](https://support.apple.com/en-tm/guide/mac-help/mchl63d14732/mac)
- [Apple: use Voice Control commands](https://support.apple.com/en-ke/guide/mac-help/mh40719/mac)
- [Apple: customize Voice Control](https://support.apple.com/en-il/guide/mac-help/mchl9899c8a5/mac)

### A local engine needs an application and an input path

`whisper.cpp` v1.9.4 supports Intel and Arm macOS. Its source documents Apple
Silicon optimizations through NEON, Accelerate, Metal, and Core ML. The model
table reports approximate memory use of 273 MiB for tiny, 388 MiB for base,
852 MiB for small, 2.1 GiB for medium, and 3.9 GiB for large. Quantization can
reduce disk and memory use. The Core ML guide warns that the first run compiles
the model to a device-specific form, so it is slower.

This is a strong local inference engine, not a complete Zen dictation product.
It does not supply a macOS consented microphone UI, global shortcut, stable app
identity, or safe text-delivery policy. The pinned Nixpkgs package is
`whisper-cpp` 1.8.4. On `aarch64-darwin` its derivation enables Metal and Core
ML by default, but a raw CLI still requires recording, model lifecycle, and
delivery code. A custom wrapper that synthesizes keyboard events would need
Accessibility permission. A clipboard-only wrapper avoids that permission but
requires the user to paste deliberately. Neither was tested here.

- [whisper.cpp v1.9.4 README and model memory table](https://github.com/ggml-org/whisper.cpp/blob/v1.9.4/README.md)
- [whisper.cpp v1.9.4 release](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.9.4)
- [Pinned Nixpkgs `whisper-cpp` 1.8.4 derivation](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/by-name/wh/whisper-cpp/package.nix)

### Voxtype is promising, but not yet a Nix Darwin package

Voxtype v1.0.1 was released 2026-08-31. Its release includes a universal macOS
binary and DMG. Its tag documentation says macOS needs Apple Silicon and macOS
13 or later, while its release asset says universal. The target profile is
Apple Silicon, so it satisfies both descriptions. Its macOS architecture says
the app uses CGEvent text output and requires Microphone, Input Monitoring, and
Accessibility. Its install guide describes local Whisper and ONNX Parakeet,
including a Parakeet Neural Engine path. That source claim is not an accuracy,
latency, or energy benchmark.

The pinned Nixpkgs `voxtype` 0.7.2 is Linux-only and declares itself a
Wayland push-to-talk daemon. It cannot be selected for Darwin. Upstream's
v1.0.1 flake also describes a Linux package, so the existing flake is not a
Darwin packaging answer. The source has macOS-specific Rust dependencies and
Swift app bundles, making a reviewed Darwin package feasible, but it must build
and preserve the signed app bundles rather than install an unadorned binary.
That identity matters because macOS TCC permissions attach to it.

Do not adopt the released DMG or Homebrew cask declaratively in this Nix
configuration. Upstream's own macOS notes say the app bundles are ad-hoc signed
and may require **Open Anyway**. They also list disabled audio feedback and
LaunchAgent conflicts. A pinned source package should first prove an arm64
build, code-signing strategy, model integrity, permission prompts, hotkey
behavior with AeroSpace, focus in Zen, cancellation, and no auto-submit.

- [Voxtype v1.0.1 release assets and date](https://github.com/peteonrails/voxtype/releases/tag/v1.0.1)
- [Voxtype v1.0.1 install guide](https://github.com/peteonrails/voxtype/blob/v1.0.1/docs/INSTALL.md)
- [Voxtype v1.0.1 macOS architecture and known issues](https://github.com/peteonrails/voxtype/blob/v1.0.1/docs/MACOS_ARCHITECTURE.md)
- [Voxtype v1.0.1 configuration and local/remote backends](https://github.com/peteonrails/voxtype/blob/v1.0.1/docs/CONFIGURATION.md)
- [Pinned Nixpkgs `voxtype` 0.7.2 derivation](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/by-name/vo/voxtype/package.nix)

## Validation and limits

On 2026-09-22, this review retrieved Apple support documentation, nix-darwin
source at `4cff07de74b50e64bdd68cd4e722ab5b6b35ee48`, Home Manager source at
`4ac5a2ae9025eab1ebece4f9df8c315fd84a738a`, Nixpkgs at
`c5c4a43b0e8056328ec4529f735cabdb8f1942bb`, whisper.cpp v1.9.4, and Voxtype
v1.0.1. It inspected the local Darwin profile, its AeroSpace configuration,
and the repository macOS preference module. The supported Fn/Globe option was
evaluated in the Darwin system configuration; the build result is reported with
the implementation, not established by this source review.

No live macOS test verified that the chosen Dictation shortcut reaches Zen,
that Apple sends address-bar audio to a server, that Voice Control can target
Zen reliably, or that either local engine has acceptable recognition quality,
latency, battery use, or thermal behavior. Apple and upstream documentation can
change after this review. The Voxtype macOS documentation differs on whether
Intel is supported, although that does not affect the selected arm64 profile.

## Implication for this repository

The selected Darwin profile now enables a small optional
[dictation module](../../modules/darwin/dictation.nix) that assigns Fn/Globe through
the typed nix-darwin option. Dictation enablement, language selection, and
privacy consent remain a user setup step in System Settings. The Fn/Globe
setting takes effect after restarting the Mac.

If local-only address-bar dictation is required, create a separate decision and
package-review task for Voxtype v1.0.1. Prefer local Whisper first because it
has the simpler dependency path. Test Parakeet only as a measured alternative.
Bind its toggle command through the already configured AeroSpace module where
possible, so the app need not own a global Input Monitoring hotkey. Direct text
delivery still needs Accessibility approval. Require manual review and Enter
submission for every search.
