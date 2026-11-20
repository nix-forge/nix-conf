# Automatic speech model updates for Handy

Reviewed: 2026-11-17. Scope: Handy 0.9.8 at
`14f6f0d31cb22a4268acfbddba3052820fd0a06e`, Parakeet Unified EN Q8_0 GGUF,
and model updates plus low-latency postprocessing on Linux/macOS.

## Answer

For this repository, prefer a **model package in nixpkgs-personal with an
automated revision/hash updater**, using the existing daily package-update
workflow. This removes hand-maintained model hashes from the desktop module,
retains reproducible model/engine combinations and ordinary Nix rollback, and
reuses existing review/deployment infrastructure. A model package alone is not
automation: it must include an updater discovered by the scheduled workflow.
Generated hashes remain integrity checks, not manual maintenance.

That approach delivers new weights with normal Nix input advancement and
deployment; it does **not** change running weights immediately after an upstream
upload. If updates must arrive independently of deployments, use a scheduled
user service built around **`huggingface_hub`** instead: retain repository,
filename, family and quantization as policy; resolve `main` to an immutable
commit, verify and validate a candidate with the installed engine, then atomically
publish durable last-good state. That is a larger integration, not a feature
Handy already supplies. Keep download/validation work outside startup and
dictation. Neither approach should silently switch model families.

For text cleanup, keep native normalization, conservative filler removal and
a small editable vocabulary. Keep generative postprocessing off for ordinary
dictation. The existing configuration already makes that distinction; no extra
model or service is necessary for basic cleanup. String operations still cost
time, but there is no second inference/network pass. No target latency bound
has been measured.

## Findings and sources

### What Handy actually updates

At the exact 0.9.8 commit:

- The catalog is compiled with `include_str!("catalog.json")`; there is no
  runtime remote catalog refresh in this path. Its descriptors contain a
  repository, filename and pinned revision. Updating the app can change the
  bundled catalog; changing an HF branch does not change the running catalog.
  [Catalog implementation][catalog], [catalog data][catalog-data].
- `download_hf_model` requests the catalog revision, but immediately succeeds
  without downloading when a matching cached or flat local file exists. Routine
  catalog regeneration intentionally does not invalidate working local models.
  A new app/catalog therefore does **not** guarantee replacement of installed
  weights. [Downloader and cache policy][manager].
- `rescan_local_models` is local discovery, exposed through a Tauri command.
  `download_model` is also a Tauri command, not a supported shell subcommand.
  The CLI supports model listing and headless WAV transcription, but no
  model-download/update command; `--transcribe-file` explicitly requires an
  installed model. [Commands][commands], [CLI][cli].
- The module's `update_checks_enabled = false` and
  `HANDY_DISABLE_UPDATER=1` express application-update policy; they do not
  configure a background model revision service. Its current preparation step provisions a Nix-store model
  symlink and reconciles settings before launch.
  [Module](../../modules/home/desktop/dictation.nix),
  [reconciler](../../modules/home/desktop/dictation-assets/reconcile/src/main.rs).

Latest upstream was also checked at Handy
`aca8985190c3ad7f361d8a80cb30f179513ed690` (2026-11-14). It still embeds a
catalog, now copied from the pinned `@handy-computer/models` package, with a
catalog/engine-version consistency check. Its cache lookup has expanded to
requested pin, `main`, then other snapshots; this is cache reuse, not fetching
new revisions. Do not assume the 0.9.8 cache algorithm applies unchanged after
an application upgrade. [Latest catalog][latest-catalog],
[latest cache implementation][latest-manager].

### Supported Hugging Face acquisition

Use the Python library rather than shell-parsing CLI output:

```python
from huggingface_hub import HfApi, hf_hub_download

repo = "handy-computer/parakeet-unified-en-0.6b-gguf"
filename = "parakeet-unified-en-0.6b-Q8_0.gguf"
info = HfApi(token=False).model_info(
    repo, revision="main", files_metadata=True, timeout=30,
)
entry = next(item for item in info.siblings if item.rfilename == filename)
candidate = hf_hub_download(
    repo_id=repo, filename=filename, revision=info.sha,
    cache_dir=updater_cache, token=False,
)
```

This is an API sketch, not a complete updater: `updater_cache`, verification,
timeouts for the full job, validation and publication remain integration work.
`info.sha` freezes the metadata/download transaction; compare the file's
`entry.lfs.sha256` and size with the downloaded bytes. Require expected metadata
and fail closed if absent. Retain the digest in local release metadata, generated
automatically rather than edited in Nix. Public, ungated repositories need no
login; `token=False` explicitly avoids incidental saved/environment credentials.
[API and file metadata][hf-api], [download API][hf-download].

The official CLI supports `hf download <repo> <filename> --revision <commit>`;
re-running against `main` checks for current content and reuses unchanged cache
objects. It does not schedule updates, test inference compatibility, or manage
last-good application state. `--local-dir` targets a local working folder with
its own download metadata; do not use the active Handy model directory as that
folder. [CLI guide][hf-cli], [CLI download source][hf-cli-source].

Direct unauthenticated HF API observation on the review date: `main` resolved
to `843b1b175ace04f5a89d379c79e2518c0d065b25`, while the configured catalog pin
is `7e948f21b7bdbac698d3318db9d350f1096f3b6c`. The Q8 file still has size
731357568 and SHA256
`4b50b6dd862bf6e346929aaf4f5eaacec003bfa3f56462d6c874b41ef2f38795`.
Thus a newer repository commit does not necessarily mean new weights; compare
content identity before validation/promotion. [Live metadata][hf-metadata],
[immutable current tree][hf-tree].

### Persistence, resolution and release pitfalls

The following is a recommended architecture, inferred from the source behavior:

1. A systemd user timer / launchd scheduled job runs independently of Handy.
   Serialize updater runs, impose a whole-job deadline, and retry only through
   later scheduled runs or bounded backoff. Download failure leaves active state
   untouched. An explicit update-now command invokes the same packaged job.
2. Keep a private updater cache and immutable releases in durable user data,
   for example `<Handy data>/model-releases/<content-digest>/`. Copy the verified
   file out of the download cache into a staging release; flush the file and
   metadata and atomically rename on the same filesystem. Never modify HF cache
   objects in place. HF snapshots are generally symlinks to shared blobs, and
   cache pruning can remove revisions. A symlink into a disposable cache is not
   sufficient last-good persistence. [HF cache contract][hf-cache].
3. Validate GGUF family/architecture/quantization and load/transcribe a small
   nonpersonal speech fixture with the **installed engine version** before
   promotion. Use a compatible validator packaged alongside that engine;
   HF provides no Handy compatibility validator. Limit validation resources and
   defer it if dictation is busy. A load or fixture pass catches some regressions,
   not all accuracy or backend failures. Do not automatically choose a different
   family, larger model or renamed filename.
4. Keep one durable `current` symlink and a recorded previous validated release.
   Publish by replacing a temporary symlink with `rename`/`os.replace`, then
   sync the parent directory for crash durability. The flat model filename can
   link through `current`. Put release metadata inside each immutable release
   so one pointer selects both bytes and metadata. Retain old bytes while an
   existing engine may still have them open; garbage-collect only older,
   unreferenced releases. Coordinate rollback and promotion under the same lock.
5. Preserve the catalog model ID in settings, but make the flat filename the
   sole managed resolution path. In **0.9.8**, lookup first tries the HF cache
   ref for the catalog pin, then `refs/main`, then
   `<Handy data>/models/parakeet-unified-en-0.6b-Q8_0.gguf`. Merely downloading
   latest `main` or replacing the flat link can leave the old pinned cache copy
   winning. Python downloads at a commit also need not create Rust's expected
   `refs/<commit>` file. Avoid manufacturing or repointing fake commit refs.
   [Exact lookup and `get_model_path`][manager].
6. For that flat-path design, launch Handy 0.9.8 with a dedicated `HF_HOME`
   containing no competing copy of this repository, and download through the
   updater's separate explicit `cache_dir`. Check this invariant during
   preparation and after app upgrades; preserve users' existing shared caches.
   Do not blindly delete them to resolve precedence. Handy's 0.9.8 delete action
   can remove an entire shared HF repository cache for the default model.
   [Cache environment and deletion][manager].
7. Change preparation so it preserves/validates the managed pointer instead of
   resetting it to the old Nix-store pin on every start. Ordinary startup uses
   only local state. Provision the first model through an explicit bootstrap job
   before enabling dictation, or retain a packaged bootstrap model. With no
   initial model and no bundled weights, first-ever offline startup cannot work.
   An already loaded model remains resident until unload/reload; promotion is
   not an immediate live-engine replacement. Let the next safe load pick it up,
   and retain rollback if that load fails.

**Known limitation:** automatic latest revisions of this fixed family need our
own scheduling, compatibility checks and atomic promotion integration. Same
repository and filename do not guarantee future compatibility with Handy 0.9.8.
HF metadata/digests protect content identity and transfer integrity, not against
a compromised publisher or model-quality regressions. Advancing upstream trust
is distinct from a reviewed immutable Nix pin.

### Nixpkgs versus nixpkgs-personal

Current upstream Nixpkgs `handy` is 0.10.0 and has
`passthru.updateScript = nix-update-script { ... };`; that updates the app's
package sources, not independently installed model state. The inspected
`whisper-cpp` package exposes a Whisper download helper, not this Parakeet model.
No ready-made Unified EN Q8 model attribute was identified in the inspected
Handy recipe and `pkgs/by-name/pa` listing. This is a scoped search, not proof
that no model package exists anywhere in Nixpkgs. [Handy package][nix-handy],
[Whisper package][nix-whisper], [Parakeet-name search scope][nix-pa].

Nixpkgs documents automatic attempts for packages exposing `passthru.updateScript`;
a successful update still needs publication, input advancement and deployment.
For a model without conventional release tags, an updater can resolve HF `main`,
record its immutable SHA, and compute the fetch hash automatically. Generic app
release discovery does not establish this model-specific policy.
[Nixpkgs update contract][nix-updates].

The package submodule already schedules daily discovered `update.py` jobs with
per-package pull requests. Its `handy-bin` currently has source metadata but no
such updater. If choosing deploy-time model updates, add a reusable model recipe
and updater **in nixpkgs-personal**, then consider upstreaming it. Packaging and
hash-generation belong there; workstation scheduling, preferences and promotion
policy belong in this repository. The existing automation does not currently
update a model hidden inside the root desktop module.
[Updater discovery](../../pkgs/scripts/update_packages.py),
[scheduled workflow](../../pkgs/.github/workflows/update-packages.yml),
[Handy binary recipe](../../pkgs/pkgs/by-name/ha/handy-bin/package.nix).

### Postprocessing without a second inference pass

The selected Unified recognizer already supplies punctuation and capitalization. [Model
card][unified-card]. Keep native deterministic cleanup; do not run a second recognizer
or a punctuation/grammar LLM by default. `post_process_enabled=false` disables
generative postprocessing, not the recognizer's native final-text normalization.
`normalize_transcription_output` trims whitespace, collapses multiple spaces, and
collapses runs of three or more identical words. It runs after both batch and streaming
output. Even these rules can alter intentional repetitions; no literal-transcription
guarantee. [Native text transforms][text-transforms], [final transcription
cleanup][transcription].

`filler_word_removal_enabled` defaults true. The built-in English rule removes
hesitations such as `um`, `uh`, `ah`, and `eh` plus repeated variants; it does not
delete ordinary semantic words like `like`, `so`, or `actually`. `custom_filler_words`
overrides the entire built-in list; empty list disables removal. For technical
dictation, an explicit short list such as `um`, `uh`, `uhm`, `umm`, `uhh`, `uhhh` is a
conservative candidate, but literal quotations or spoken identifiers can still contain
those tokens. Keep editable and validate on representative output. [Native filler
rules][text-transforms], [settings defaults][settings].

Custom words are fuzzy replacements in this pinned streaming path, using Levenshtein and
Soundex on up to three-word spans. They are not model retraining, a spelling dictionary,
or guaranteed correct vocabulary biasing. Keep a short curated set of actual recurring
product names; leave threshold at upstream default initially. Large dictionaries
increase string-matching work and false substitutions. Avoid global replacement of
ambiguous homophones or unrestricted number conversion; version numbers, units, dates,
and code identifiers need context. [Fuzzy vocabulary implementation][text-transforms],
[pinned streaming correction path][transcription].

These are local string operations with expected small overhead for ordinary short
dictation, but no measured bound or zero-cost claim is justified. AI postprocessing is
awaited before final paste; network or a second model load/generation adds serial
latency. Keep default plain dictation, with an optional separately invoked cleanup
shortcut only for prose if requested. Even a warm local model or Apple Intelligence
cannot guarantee no added time or preserved wording. [Awaited postprocessing before
paste][actions], [Handy postprocessing documentation][postprocessing-docs].

## Validation and limits

Read the local module/reconciler and package automation, fetched exact Handy
0.9.8 and current upstream source, inspected current Nixpkgs recipes, and queried
public HF metadata without credentials. No weights were downloaded, no inference
or failure-recovery tests ran, and no system build, deployment, package or
submodule edits were performed. Focused rumdl 0.3.2 and typos 1.52.0 checks
passed for this note. The HF library source checked was
`e0362b934eb8b73149db5cdaf528093c3eac4de4`; pin the packaged version and verify
these APIs before implementation. The local Nixpkgs package evaluates to
`huggingface-hub` 2.4.0. The research index now links this combined update and
postprocessing investigation. The research phase made no runtime configuration
or package changes; the implementation follow-up below records the later work. The reconciler link follows its concurrent Rust migration;
its inspected behavior still installs the selected Nix-store model symlink.

## Implementation follow-up

The [model package](../../pkgs/pkgs/by-name/pa/parakeet-unified-en-gguf/README.md)
now owns generated source pins and a discovered daily updater. The
[dictation module](../../modules/home/desktop/dictation.nix) consumes its model
identity, filename and path. A distinct `nix-` filename and its stem as a local
model ID avoid catalog/HF-cache precedence without deleting shared downloads.
This is simpler than a dedicated cache for the reproducible package approach.
The updater verifies immutable bytes, size and the
GGUF header before publishing a pin; this is an integrity/format check, not an
inference compatibility or accuracy test. Native filler removal is explicit;
custom vocabulary stays editable and generative postprocessing remains disabled.
The runtime updater alternative above is not implemented. Updates still require
normal input advancement and deployment after the package update is published.

The data package builds on Linux. The package repository's `just check` passes,
including all exported-system evaluations, and its discovered native updater
passes a live `--dry-run --refresh`. Disposable-checkout probes exercised
preview/check, verified apply, idempotence and rejection of an invalid filename.
These are manual verification results, not a retained behavioral test suite.
Both home profiles evaluate the managed local model metadata. Complete host
validation is currently blocked by an unrelated source-view gap in the concurrent
runtime-helper migration; no activation or live microphone/paste check ran.

[catalog]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/catalog/mod.rs
[catalog-data]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/catalog/catalog.json
[manager]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/managers/model.rs
[commands]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/commands/models.rs
[cli]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/cli.rs
[latest-catalog]: https://github.com/cjpais/Handy/blob/aca8985190c3ad7f361d8a80cb30f179513ed690/src-tauri/src/catalog/mod.rs
[latest-manager]: https://github.com/cjpais/Handy/blob/aca8985190c3ad7f361d8a80cb30f179513ed690/src-tauri/src/managers/model.rs
[hf-api]: https://huggingface.co/docs/huggingface_hub/package_reference/hf_api#huggingface_hub.HfApi.model_info
[hf-download]: https://huggingface.co/docs/huggingface_hub/guides/download
[hf-cache]: https://huggingface.co/docs/huggingface_hub/guides/manage-cache
[hf-cli]: https://huggingface.co/docs/huggingface_hub/guides/cli
[hf-cli-source]: https://github.com/huggingface/huggingface_hub/blob/e0362b934eb8b73149db5cdaf528093c3eac4de4/src/huggingface_hub/cli/download.py
[hf-metadata]: https://huggingface.co/api/models/handy-computer/parakeet-unified-en-0.6b-gguf?blobs=true
[hf-tree]: https://huggingface.co/handy-computer/parakeet-unified-en-0.6b-gguf/tree/843b1b175ace04f5a89d379c79e2518c0d065b25
[nix-handy]: https://github.com/NixOS/nixpkgs/blob/c4838ccf2b208d44ff51cd76e7ede2749f2cb5f9/pkgs/by-name/ha/handy/package.nix
[nix-whisper]: https://github.com/NixOS/nixpkgs/blob/c4838ccf2b208d44ff51cd76e7ede2749f2cb5f9/pkgs/by-name/wh/whisper-cpp/package.nix
[nix-pa]: https://github.com/NixOS/nixpkgs/tree/c4838ccf2b208d44ff51cd76e7ede2749f2cb5f9/pkgs/by-name/pa
[nix-updates]: https://nixos.org/manual/nixpkgs/unstable/#var-passthru-updateScript

[text-transforms]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/audio_toolkit/text.rs
[transcription]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/managers/transcription.rs
[settings]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/settings.rs
[actions]: https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/actions.rs
[postprocessing-docs]: https://handy.computer/docs/post-processing
[unified-card]: https://huggingface.co/nvidia/parakeet-unified-en-0.6b
