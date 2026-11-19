# Local English dictation models and Handy integration

Reviewed: 2026-11-17. Scope: Handy **v0.9.8**, commit
`14f6f0d31cb22a4268acfbddba3052820fd0a06e`; Apple M4 Pro macOS and Linux
with NVIDIA RTX 4070 plus an AMD integrated GPU. This is a source-based
recommendation, not a workstation benchmark.

## Answer

Use **Parakeet Unified EN 0.6B, GGUF Q8_0**, with GPU selection enabled and
**five-minute idle unloading** as the balanced English dictation default on
both platforms. Prefer Metal on Apple Silicon and Vulkan on the RTX 4070.
Automatic CPU fallback runs the same GGUF; ONNX Parakeet v2 remains a separate
rollback option. This replaces the earlier
accuracy-first Cohere recommendation: responsiveness and good English accuracy
are now joint requirements. Unified has a real GPU encoder path in the locked
engine; this is not inferred merely from a GPU Cargo feature.

The choice is practical rather than a demonstrated winner on these machines.
Upstream publishes warm GPU results for Unified, and its Q8 export has measured
English accuracy. Neither proves its total dictation latency or correction
rate against ONNX Parakeet v2 on the target hardware.
[Unified port and results][unified-port], [engine loader][parakeet-engine].

## Findings and sources

### Accuracy and speed evidence

NVIDIA reports **5.91% offline average English WER** for Unified, compared with
6.04% for v2 in the same table. Its streaming results differ from offline.
Cohere reports **5.42%** average English WER for its 2B model. These normalized
publisher results do not measure Handy's quantized exports, punctuation,
identifiers, microphone conditions, or accent-specific correction effort.
[NVIDIA card](https://huggingface.co/nvidia/parakeet-unified-en-0.6b#asr-performance-wo-pnc),
[Cohere card](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026#results).

The port maintainer reports Unified **Q8_0 1.60% WER** versus F32 1.59% on full
LibriSpeech test-clean (2,620 utterances, batch 1), and Q8_0 3.99% on FLEURS
test English. These are narrower evaluations than the publisher's average;
do not compare their absolute values to that average. Q8 is the bundled
catalog default and avoids assuming that stronger quantization is faster.
[Port results][unified-port], [Handy catalog][catalog].

Concrete speed evidence is available in the maintainer's pinned
[benchmark records][speed-records] and [method/results][unified-port]. For the
11-second `jfk` sample, Unified Q8_0 warm **compute** time is 58.6 ms on M4 Max
Metal versus 285.3 ms CPU; Ryzen 7 PRO 4750U / Radeon RADV RENOIR takes about
448 ms Vulkan versus 712 ms CPU. These are mel + encode + decode, mean of
three iterations after one warmup, measured 2026-09-14 at engine revisions
`77b0c93` (Apple) and `cd0ea568` (AMD). They exclude model loading and Handy's
recording, VAD, stream buffering, paste, and UI costs. The AMD records are
marked thermal-gated. They are evidence for working acceleration, **not M4 Pro
or RTX 4070 timings**, and were not measured at the locked engine revision.

Q4_K_M takes 60 ms on the same Apple/Metal sample versus Q8's 58.6 ms, so
smaller files do not establish lower latency. Cohere Q8 GGUF takes 143.8 ms in
the Apple/Metal benchmark, versus Unified's 58.6 ms; this supports a model-family
tradeoff but **does not benchmark `cohere-int8` ONNX**. No matched target-hardware
ONNX/GGUF comparison was run. Ignore Handy's catalog `speed_score` as a hardware
benchmark. [Unified records][speed-records], [Cohere records][cohere-speed].

### Trace through the exact engine

Handy's [lockfile][lock] pins `transcribe-cpp` and `transcribe-cpp-sys` **0.2.4**;
both published crates identify source commit
`4807edaf210d0d7e8a6f7fb2a44b65966a2797f0`. Legacy ONNX uses `transcribe-rs`
**0.3.8**, source `49356e1359f1725adac9d491aeb892be37b15d89`.
[Handy dependencies][deps] enable Metal on macOS and Vulkan + dynamic backends
on Linux, while ONNX enables only `onnx`, without CUDA, ROCm, or CoreML providers.

The [Handy loader][loader] routes catalog GGUF entries through `Model::load_with`
with backend/device options, reads actual model capabilities, and logs the
**bound** backend and device. Some comments/errors still say “whisper”; they do
not restrict dispatch to that family. The engine's
[architecture registry][architectures] dispatches Parakeet and Cohere too.

For Parakeet, [load()][parakeet-engine] calls shared `init_backends`, allocates
weights on the primary backend, and computes the encoder using the backend
scheduler. [Encoder policies][encoder] explicitly handle Metal/Vulkan kernel
differences. The predictor/joint transducer decoder is copied to host storage
and runs on CPU; mel preprocessing and unsupported graph operations can also
use CPU. Thus **Unified EN GGUF supports partial Metal/Vulkan acceleration**,
not end-to-end GPU execution or guaranteed acceleration of every operation.
The [shared backend plan][backend-plan] keeps CPU fallback. Cohere GGUF also
initializes that plan and schedules encoder/decoder graphs; **Cohere ONNX is a
different path**. [Cohere engine][cohere-engine].

The legacy `parakeet-tdt-0.6b-v2` and `cohere-int8` ONNX entries remain CPU
models in this build. Setting `ort_accelerator = "cuda"` or `"rocm"` cannot
compile in an absent provider, and Metal is not an ONNX accelerator here.
[Provider selection](https://github.com/cjpais/transcribe-rs/blob/49356e1359f1725adac9d491aeb892be37b15d89/src/onnx/session.rs),
[Handy dependencies][deps].

### Concrete provisioning and settings

Use these exact values from Handy's **bundled**, versioned [catalog][catalog]:

```text
selected_model:
  handy-computer/parakeet-unified-en-0.6b-gguf/parakeet-unified-en-0.6b-Q8_0.gguf
repo: handy-computer/parakeet-unified-en-0.6b-gguf
revision: 7e948f21b7bdbac698d3318db9d350f1096f3b6c
filename: parakeet-unified-en-0.6b-Q8_0.gguf
size_bytes: 731357568
sha256: 4b50b6dd862bf6e346929aaf4f5eaacec003bfa3f56462d6c874b41ef2f38795
```

Immutable [model download](https://huggingface.co/handy-computer/parakeet-unified-en-0.6b-gguf/resolve/7e948f21b7bdbac698d3318db9d350f1096f3b6c/parakeet-unified-en-0.6b-Q8_0.gguf).
This is **one GGUF file**, not an ONNX archive. Put it at
`<Handy app data>/models/parakeet-unified-en-0.6b-Q8_0.gguf`, or use Handy's
revision-aware Hugging Face cache. Do not turn the slash-containing model ID
into a nested model directory. Handy first checks its HF cache, then this
flat-file fallback. [ID construction][catalog-code],
[path resolution][model-path]. App data is
`$HOME/Library/Application Support/com.pais.handy` on macOS and
`$XDG_DATA_HOME/com.pais.handy` on Linux (normally `$HOME/.local/share`).
The repository [reconciler](../../modules/home/desktop/dictation-assets/reconcile/src/main.rs)
and [module](../../modules/home/desktop/dictation.nix) now provision this flat
GGUF file from the automatically updated `parakeet-unified-en-gguf` package
through a Nix-store symlink. The package now exposes a distinct `nix-` filename
and local model ID for Handy to prevent cached catalog weights taking precedence.
The catalog identity below remains useful upstream provenance, not the managed
local selection ID.

Recommended preference fragment (merge with existing shortcuts/paste settings):

```json
{
  "selected_model": "handy-computer/parakeet-unified-en-0.6b-gguf/parakeet-unified-en-0.6b-Q8_0.gguf",
  "selected_language": "en",
  "model_unload_timeout": "min5",
  "transcribe_accelerator": "auto",
  "transcribe_gpu_device": null,
  "ort_accelerator": "cpu",
  "overlay_style": "live",
  "overlay_position": "bottom"
}
```

On **M4 Pro**, start with `auto`: Metal is compiled in, and the Apple Silicon
GPU is the intended backend. On **Linux**, `auto` probes discrete GPUs before
integrated GPUs, so the RTX 4070 should precede the AMD iGPU if both Vulkan
devices initialize. This build uses **Vulkan, not CUDA**, for GGUF. For a stable
explicit choice, select the RTX in Handy's device UI and preserve its returned
key with `transcribe_accelerator = "gpu"` and `transcribe_gpu_device` set to
that **string key**, not a numeric index. The key encodes
`[backend, identity-kind, identity]` as JSON; do not invent a PCI identity.
`gpu` with no device is migrated to `auto`. Verify the bound device in Handy's
load log; automatic selection can fall back. Linux needs a working NVIDIA
Vulkan ICD and loadable backend. Using the AMD iGPU to avoid waking the RTX
is a possible power tradeoff, not an established speed improvement.
[Device settings and selection][device-selection],
[engine probe ordering][probe-order], [settings][settings].

### Warm loading and streaming latency

`model_unload_timeout = "min5"` retains the engine between nearby dictations;
`"immediately"` drops it after each completed transcription. Five minutes
avoids repeated parsing, weight upload, session creation, and lazy preparation,
while eventually returning memory. The idle watcher checks every ten seconds
and refreshes activity while recording; this is approximate idle eviction,
not exact five-minute residency. It does not remove the first cold load or
guarantee a specific amount of time saved. Resident memory includes runtime
buffers and host decoder weights, not just the 731 MB file. [Unload logic][loader],
[timeout values][settings].

Handy starts streaming from model capability, independently of overlay style.
A usable finalized stream is pasted directly; batch transcription is the fallback
when no usable stream exists. The live overlay exposes previews, but changing
it to `minimal` does **not** select offline decoding. Unified uses buffered
streaming: its default is 5.6 s left context, 1.04 s chunk, 1.04 s right context
(**2.08 s initial buffering**, not a promised 160 ms Handy preview). Handy passes
default stream options and exposes no preference here for the engine CLI's
chunk/right-context overrides. Finalization flushes retained context and the
tail, rather than ordinarily rerunning the entire recording offline.
[Handy recording/finalization][actions], [stream options][loader],
[engine streaming details][unified-port].

Streaming can move work into recording time and shorten release-to-paste wait
for longer utterances, provided inference keeps pace. It still computes repeated
left context and pays final-tail work; short commands may gain little and need
not match offline WER. For fast offline dictation without this tradeoff, compare
Parakeet v2 (GGUF for GPU, legacy ONNX for CPU). Do not claim Unified's offline
5.91% average as Handy's streaming accuracy.

### Superseded accuracy-first choice and rollback

The earlier recommendation selected **`cohere-int8`**, English, immediately
unloaded, on the strength of Cohere's lower published average WER. That choice
is **superseded for balanced daily dictation**, not disproved as an accuracy
candidate. It is a larger, non-streaming 2B model using CPU in this build.
If revisiting it, retain warm loading first; a GPU Cohere GGUF evaluation is
also possible but is a different integration.

Its pinned [archive](https://blob.handy.computer/cohere-int8.tar.gz) SHA256 is
`ea2257d52434f3644574f187dcdcf666e302cd11b92866116ab8e14cd9c887f0`.
The old note recorded a matching archive hash and listing; those checks were
not repeated here. The directory contains `cohere-encoder.int8.onnx`, external
`cohere-encoder.int8.onnx.data`, `cohere-decoder.int8.onnx`, and `tokens.txt`.
Keep the external data beside the encoder; exclude AppleDouble metadata.
[Registry][model-registry].

CPU rollback: ID `parakeet-tdt-0.6b-v2`,
[archive](https://blob.handy.computer/parakeet-v2-int8.tar.gz), SHA256
`ac9b9429984dd565b25097337a887bb7f0f8ac393573661c651f0e7d31563991`;
flatten `parakeet-tdt-0.6b-v2-int8/` as required by the reconciler. Keep `min5`.
The prior note recorded a matching hash; this reassessment did not re-download it.
[Registry][model-registry].

### Existing integration constraints

Handy supplies the same model/settings UI on both platforms. Linux defaults to
no overlay, so explicitly choose `live` or `minimal`; overlay and native paste
still need compositor testing. External `--toggle-transcription` commands are
paired toggles, not separate idempotent start/stop commands. A compositor binding
on press/release can invert state after a missed/duplicate event. Native
`handy_keys` + `shortcut_activation = "push_to_talk"` supports
`option_left+space` on macOS; Linux evdev/uinput permissions require separate
integration consideration. These constraints survive the model change.
[Overlay](https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/overlay.rs),
[coordinator](https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/transcription_coordinator.rs),
[settings][settings].

## Validation and limits

Read repository configuration and immutable upstream source; downloaded the
locked crate source archives and inspected their embedded C++ implementations
and VCS identities; all three crate archive checksums matched Handy’s lockfile.
Catalog pin values, Markdown reference links, portable paths, and
`git diff --check` were checked. The supplied local Nix store source was **absent on the
research host**, so the inspection used Handy commit `14f6f0d…` recorded by the
existing note, not that store tree. Treat equivalence with the requested store
path and any package patches as unverified until checked on its owning host.
No new model download/hash verification, inference, public-audio benchmark,
microphone access, app/UI test, build, activation, or implementation edit ran.
Only this research note was changed.

Validate the same consented English recordings on each target: compare warm
and cold press-to-ready and release-to-paste latency, correction effort,
punctuation/names, and memory; record actual backend/device and stream versus
fallback. In particular, compare warm Unified GGUF against warm v2 ONNX before
claiming a target-specific speedup. No target M4 Pro/RTX 4070 benchmark or shipped
binary runtime was verified. NVIDIA's current Unified card uses the NVIDIA
Open Model License, while the port/catalog labels it CC-BY-4.0; consult upstream
terms rather than treating catalog metadata as authoritative.

## Implication for this repository

Provision the pinned flat GGUF, select Unified Q8_0 with `min5`, allow Metal or
RTX Vulkan, and keep v2 ONNX documented as an optional rollback. The module
now applies this choice through the existing reconciliation owner. Configuration
and model provisioning do not establish runtime acceptance. Keep cloud post-processing disabled for local-only
operation.

[catalog]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/catalog/catalog.json
[catalog-code]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/catalog/mod.rs
[lock]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/Cargo.lock
[deps]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/Cargo.toml
[loader]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/managers/transcription.rs
[device-selection]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/managers/transcription.rs#L2047
[settings]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/settings.rs
[actions]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/actions.rs#L437
[model-path]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/managers/model.rs#L2556
[model-registry]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/managers/model.rs
[unified-port]: https://github.com/handy-computer/transcribe.cpp/blob/4807edaf210d0d7e8a6f7fb2a44b65966a2797f0/docs/models/parakeet-unified-en-0.6b.md
[speed-records]: https://github.com/handy-computer/transcribe.cpp/blob/4807edaf210d0d7e8a6f7fb2a44b65966a2797f0/catalog/parakeet-unified-en-0.6b.json
[cohere-speed]: https://github.com/handy-computer/transcribe.cpp/blob/4807edaf210d0d7e8a6f7fb2a44b65966a2797f0/catalog/cohere-transcribe-03-2026.json
[architectures]: https://github.com/handy-computer/transcribe.cpp/blob/4807edaf210d0d7e8a6f7fb2a44b65966a2797f0/src/transcribe-arch.cpp
[parakeet-engine]: https://github.com/handy-computer/transcribe.cpp/blob/4807edaf210d0d7e8a6f7fb2a44b65966a2797f0/src/arch/parakeet/model.cpp
[encoder]: https://github.com/handy-computer/transcribe.cpp/blob/4807edaf210d0d7e8a6f7fb2a44b65966a2797f0/src/arch/parakeet/encoder.cpp
[backend-plan]: https://github.com/handy-computer/transcribe.cpp/blob/4807edaf210d0d7e8a6f7fb2a44b65966a2797f0/src/transcribe-load-common.cpp
[probe-order]: https://github.com/handy-computer/transcribe.cpp/blob/4807edaf210d0d7e8a6f7fb2a44b65966a2797f0/src/transcribe-backend.cpp#L94
[cohere-engine]: https://github.com/handy-computer/transcribe.cpp/blob/4807edaf210d0d7e8a6f7fb2a44b65966a2797f0/src/arch/cohere/model.cpp
