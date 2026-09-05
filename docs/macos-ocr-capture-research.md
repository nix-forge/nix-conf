# macOS OCR capture research

Research date: 2026-09-02; product decision updated 2026-09-04

> Historical note: the review and broad target design below describe the
> original Python/Swift helper and the first feature-rich redesign. They remain
> useful implementation research, but they no longer describe the chosen
> product. After live testing, the custom AppKit selector, progress HUD, review,
> feedback, speech, history, extra capture modes, and clipboard policy were
> removed. The package README is the current behavior reference.

## Current native-fidelity decision

The tool is now deliberately a small OCR add-on to macOS Screenshot. Swift
launches `/usr/sbin/screencapture -i -s -c -d`, reads the PNG that macOS places
on the pasteboard, runs local Vision text recognition, writes ordinary text to
the pasteboard, and exits. This makes the system responsible for the exact
Shift-Command-4 cursor, coordinate display, region movement, Escape behavior,
multi-display behavior, permission UI, and sound.

This choice differs from Vorssaint's custom multi-tool overlay. Vorssaint's
overlay is appropriate for a standalone suite with window highlighting, a
loupe, repeat capture, and tool switching. It is not appropriate when the
product requirement is strict behavioral identity with macOS Screenshot. Apple
also describes ScreenCaptureKit's sharing picker in terms of displays,
applications, and windows rather than arbitrary rectangular still-image
regions, so it is not a substitute for the Shift-Command-4 interaction.

The child-process TCC concern documented by Vorssaint remains a known tradeoff.
The package mitigates it by launching from a stable copied and signed app bundle
and by asking `screencapture` to display its own errors graphically. A live test
on the target Mac confirmed that cancellation leaves the pasteboard generation
unchanged, while a completed capture advances it and publishes PNG and TIFF.
That distinction is now the cancellation contract.

## Short answer

The product is **Vorssaint**, not "Vorrisant." This repository packages
Vorssaint 3.3.2 from commit `fc302b67b509bf20fdb10132d8df2c23fb492ece`.
The old GitHub owner in the package source redirects to the current official
repository, `vorssaintapp/vorssaint-utils`. [Local package
pin](../pkgs/pkgs/by-name/vo/vorssaint/source.nix) [Official 3.3.2
source](https://github.com/vorssaintapp/vorssaint-utils/tree/fc302b67b509bf20fdb10132d8df2c23fb492ece)

Vorssaint does have a screenshot-to-text tool. Its strongest work is not a
novel OCR model. It combines Apple's on-device Vision recognizer with a polished,
in-process capture surface and a deliberately short path to the clipboard.

Your implementation has a good base. It builds an optimized native Vision
executable, runs OCR locally, exposes accuracy and language settings through
typed Nix options, distinguishes cancellation from failure, uses a private
temporary file, and deletes that file after use. Its main design problem is the
split between the executable that checks Screen Recording permission and the
separate `/usr/sbin/screencapture` process that obtains pixels. Vorssaint moved
away from this exact arrangement after it produced silent failures on recent
macOS releases. The best next version is one native process that owns capture,
OCR, clipboard output, cancellation, and feedback.

## Scope and source policy

This review covers the current worktree implementation in
[`ocr-capture.nix`](../modules/home/macos/ocr-capture.nix),
[`ocr_capture.py`](https://github.com/nix-forge/nix-conf/blob/9d39e12d9a394c6459e98f3b58d08f8069723710/modules/home/macos/ocr_capture.py), and
[`ocr_capture.swift`](https://github.com/nix-forge/nix-conf/blob/9d39e12d9a394c6459e98f3b58d08f8069723710/modules/home/macos/ocr_capture.swift). The deployed
host enables the module with its defaults, so it currently uses accurate Vision
recognition, automatic language detection, language correction, balanced text
cleanup, and `cmd-shift-7`. [Host
configuration](../homes/macbook-pro-m4/local/ocr-capture.nix)

Claims about other tools come from their official source, documentation, or
vendor documentation. Product-site performance numbers are identified as
vendor claims rather than independent measurements.

## How Vorssaint implements screen OCR

### Capture architecture and interaction

Vorssaint has one native `ScreenCaptureService` for screenshots, recordings,
screen OCR, and color picking. The OCR action starts this service in text mode,
but the shared overlay can switch tools before the user confirms a selection.
It refuses a second simultaneous session and requests Screen Recording access
only when a selected tool needs it. The result is an in-memory `CGImage` routed
to `ScreenTextService`. [Shared capture
service](https://github.com/vorssaintapp/vorssaint-utils/blob/fc302b67b509bf20fdb10132d8df2c23fb492ece/Sources/Vorssaint/Services/QuickTools/ScreenCaptureService.swift#L28-L31)
[Selection and routing](https://github.com/vorssaintapp/vorssaint-utils/blob/fc302b67b509bf20fdb10132d8df2c23fb492ece/Sources/Vorssaint/Services/QuickTools/ScreenCaptureService.swift#L103-L220)

The selection controller creates one borderless panel per display. It supports
a frozen screenshot while selecting or a live transparent selection, excludes
its own capture UI, and remembers the last region. Mouse and keyboard paths
cover a dragged region, a clicked window, Enter for a display, Escape to cancel,
Space to move the region, and `R` to repeat the previous region. The overlay
also names the current purpose, highlights selectable windows, shows pixel
dimensions, and can display a loupe. [Selection controller
overview](https://github.com/vorssaintapp/vorssaint-utils/blob/fc302b67b509bf20fdb10132d8df2c23fb492ece/Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift#L8-L17)
[Keyboard handling](https://github.com/vorssaintapp/vorssaint-utils/blob/fc302b67b509bf20fdb10132d8df2c23fb492ece/Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift#L231-L320)

Pixel acquisition uses ScreenCaptureKit. For region capture it sets a
`sourceRect`, computes output size at the display's backing scale, emits sRGB,
controls cursor inclusion, and filters the app's protected windows out of the
capture. `SCScreenshotManager` returns a `CGImage`; OCR does not need to encode
a PNG or pass a filesystem path. [Vorssaint capture
engine](https://github.com/vorssaintapp/vorssaint-utils/blob/fc302b67b509bf20fdb10132d8df2c23fb492ece/Sources/Vorssaint/Services/QuickTools/ScreenshotCaptureEngine.swift#L35-L65)
[Apple `SCScreenshotManager`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)

The source explains why Vorssaint stopped delegating selection to the system
`screencapture` command. macOS can judge the child command separately from the
allowed app. That led to a dead-looking tool with no crosshair and no useful
error. Keeping selection and capture inside the permitted process fixed that
identity split. [Vorssaint's source comment for issue
364](https://github.com/vorssaintapp/vorssaint-utils/blob/fc302b67b509bf20fdb10132d8df2c23fb492ece/Sources/Vorssaint/Services/QuickTools/ScreenTextService.swift#L7-L15)

### OCR settings and result ordering

Vorssaint first runs optional QR detection. A QR result wins and opens a review
panel. If no code is found, it runs `VNRecognizeTextRequest` on a
user-initiated background queue with accurate recognition, automatic language
detection, and language correction. It filters locale-derived fallback
languages against Vision's supported set. If the accurate pass returns no
lines, it tries the fast model with automatic language detection disabled.
Each observation contributes only its top candidate. [OCR
pipeline](https://github.com/vorssaintapp/vorssaint-utils/blob/fc302b67b509bf20fdb10132d8df2c23fb492ece/Sources/Vorssaint/Services/QuickTools/ScreenTextService.swift#L54-L132)

Apple documents these as genuinely different recognition paths. Accurate uses
a neural network and additional analysis; fast uses character detection and a
smaller model. Both run on the device. Language correction is an optional later
phase. Apple also exposes ordered recognition languages, supported-language
queries, custom vocabulary, confidence values, and a minimum text-height
control. [Apple text-recognition
guide](https://developer.apple.com/documentation/vision/recognizing-text-in-images)
[Vision request options](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)

Vorssaint reduces each observation to text plus `minX` and `midY`. It buckets
the normalized vertical coordinate into roughly 50 rows, sorts rows from top to
bottom, then sorts within a row from left to right. The current upstream branch
can either preserve these line breaks or join them into a paragraph. Its joiner
avoids inserting spaces between Han, kana, and CJK punctuation while retaining
Korean word spaces. This is a useful script-aware detail, but it is not document
layout analysis and will interleave some multi-column pages. [Pinned 3.3.2
ordering](https://github.com/vorssaintapp/vorssaint-utils/blob/fc302b67b509bf20fdb10132d8df2c23fb492ece/Sources/Vorssaint/Services/QuickTools/QuickToolsSupport.swift#L124-L147)
[Current upstream paragraph
joiner](https://github.com/vorssaintapp/vorssaint-utils/blob/a00de832b118519fa34b81ab471fa6fd00f95bd7/Sources/Vorssaint/Services/QuickTools/QuickToolsSupport.swift#L124-L177)

### Privacy, output, and failure behavior

OCR stays on-device. The service receives a `CGImage`, writes recognized text
to the system pasteboard, and shows a small copied or no-text HUD. The official
privacy policy says screen OCR uses Apple Vision, sends no capture or recognized
text away, and deletes its temporary capture after recognition. Screen
Recording permission is optional and only gates features that require screen
pixels. [Privacy
policy](https://github.com/vorssaintapp/vorssaint-utils/blob/main/docs/PRIVACY.md#what-it-reads-and-where-that-stays)
[Permissions](https://github.com/vorssaintapp/vorssaint-utils/blob/main/docs/PERMISSIONS.md#screen-recording)

QR output is treated more carefully than plain text. Vorssaint displays the
decoded payload before copying or opening it, accepts only one `http` or `https`
URL with a host, and refuses arbitrary schemes. [URL
validation](https://github.com/vorssaintapp/vorssaint-utils/blob/a00de832b118519fa34b81ab471fa6fd00f95bd7/Sources/Vorssaint/Services/QuickTools/QuickToolsSupport.swift#L222-L235)

The narrow workflow has limits. A generation counter suppresses stale UI
completion, but it does not cancel work already running in Vision. A failed
`handler.perform` is converted to an empty result and is ultimately shown as
"no text," so the user cannot distinguish an empty selection from an OCR
failure. There is no confidence review, alternate-candidate UI, preprocessing,
custom vocabulary, editable result, OCR-specific history, table output, or
multi-region selection in the 3.3.2 OCR service. These are observations from
the same source, not claims from Vorssaint's marketing.

## Useful patterns from other implementations

| Implementation | What its source or official docs demonstrate | Lesson for this module |
| --- | --- | --- |
| PowerToys Text Extractor | One overlay per display, frozen screen background, in-overlay language selection, Escape cancellation, Shift-drag to reposition, one-click word capture, a single-line toggle, and a table mode. It uses Windows' on-device `OcrEngine`, pads tiny selections, scales ordinary captures by 1.5 while respecting the engine's maximum dimension, and catches clipboard failure. [Overlay source](https://github.com/microsoft/PowerToys/blob/ef22425b767260c18ea1341408878029c0c04346/src/modules/PowerOCR/PowerOCR/OCROverlay.xaml.cs#L55-L120) [OCR and adaptive scaling](https://github.com/microsoft/PowerToys/blob/ef22425b767260c18ea1341408878029c0c04346/src/modules/PowerOCR/PowerOCR/Helpers/ImageMethods.cs#L121-L203) [Official usage guide](https://learn.microsoft.com/en-us/windows/powertoys/text-extractor) | Put the few settings that change a capture, especially language and output shape, in the capture surface. Upscale or pad only when image dimensions justify it. Keep a hard input bound. |
| NormCap | The capture is converted to RGB, enlarged by 2, and padded by 80 pixels with a sampled edge color before Tesseract. Tesseract returns word boxes and layout IDs. Scored transformers choose single-line, multi-line, paragraph, email, or URL rendering, while a user can disable parsing and get raw OCR. QR and barcode detection can run first. [Preprocessing](https://github.com/dynobo/normcap/blob/08bd57ed5124779a259876835ecd00f468add421/normcap/detection/ocr/enhance.py#L30-L101) [Recognition](https://github.com/dynobo/normcap/blob/08bd57ed5124779a259876835ecd00f468add421/normcap/detection/ocr/recognize.py#L32-L94) [Parser selection](https://github.com/dynobo/normcap/blob/08bd57ed5124779a259876835ecd00f468add421/normcap/detection/ocr/transformer.py#L10-L82) | Separate recognition observations from rendering. Make cleanup an explicit output profile and retain a literal raw mode. Benchmark preprocessing on a fixture set before enabling it. |
| Text Grab | Full-screen capture retries without closing when nothing is found; one click can capture a word from its bounding box. A persistent movable frame supports repeated capture. Results can go directly to the clipboard or an editable plain-text, Markdown, or spreadsheet view. It also has file and folder input, CLI modes, reusable cleanup/extraction templates, and direct UI Automation extraction when native text exists. OCR remains local. [Official feature and architecture description](https://github.com/TheJoeFin/Text-Grab#choose-from-four-modes) | A fast copy path and a review path can coexist. Repeated capture, editable output, and reusable transformations matter more than a large settings page. Where an accessibility API can return exact text, prefer it to OCR. |
| TRex 2.0 | Its native macOS engine abstraction supports Vision, Tesseract, and optional model providers. The Vision path uses explicit orientation, custom words, `minimumTextHeight = 0`, and confidence aggregation. It offers multi-region and watch workflows, table output, capture history, and a fallback path with a five-second timeout for alternate engines. History is enabled by default with a 100-entry default limit, although the user can disable it. [Vision engine](https://github.com/amebalabs/TRex/blob/877b14b7d013b4629f5c54d7165ba66c666bded2/Packages/TRexCore/Sources/TRexCore/OCREngine.swift#L212-L287) [Routing and timeout](https://github.com/amebalabs/TRex/blob/877b14b7d013b4629f5c54d7165ba66c666bded2/Packages/TRexCore/Sources/TRexCore/TRexCore.swift#L589-L735) [History defaults](https://github.com/amebalabs/TRex/blob/877b14b7d013b4629f5c54d7165ba66c666bded2/Packages/TRexCore/Sources/TRexCore/Preferences.swift#L427-L448) [2.0 release](https://github.com/amebalabs/TRex/releases/tag/v2.0.0) | Custom vocabulary, bounded fallbacks, multi-region capture, and structured output are worthwhile advanced features. Do not copy its history storage blindly: current source writes recognized text and JPEG thumbnails to Application Support. [History storage](https://github.com/amebalabs/TRex/blob/877b14b7d013b4629f5c54d7165ba66c666bded2/Packages/TRexCore/Sources/TRexCore/CaptureHistoryStore.swift#L34-L100) |

TextSniper also advertises text-to-speech for captured text as an accessibility
feature. That is a sensible optional destination for recognized text, although
its closed source does not reveal the OCR architecture. [TextSniper official
site](https://www.textsniper.app/#beyond-text-recognition)

Shottr reports a 17 ms screen grab and roughly 165 ms to present its screenshot
UI. Treat those as vendor-reported interaction targets, not comparable benchmark
results. [Shottr official site](https://www.shottr.cc/)

## Review of the current implementation

### What is already good

- The OCR engine is compiled once with optimization and whole-module
  optimization. Runtime capture does not invoke the Swift compiler, and the
  build has strict dependencies. [Build](../modules/home/macos/ocr-capture.nix#L12-L50)
- Recognition is local Apple Vision. There is no network code or cloud
  credential path.
- Accurate and fast modes, ordered preferred languages, language correction,
  automatic language detection, and two cleanup profiles are declarative Nix
  options. [Options](../modules/home/macos/ocr-capture.nix#L75-L127)
- The helper passes subprocess arguments as arrays and passes notification text
  through environment variables. It does not interpolate recognized or error
  text into AppleScript source. [Notification and
  capture](https://github.com/nix-forge/nix-conf/blob/9d39e12d9a394c6459e98f3b58d08f8069723710/modules/home/macos/ocr_capture.py#L68-L109)
- `NamedTemporaryFile` creates the PNG with user-only permissions under normal
  Python behavior. The helper deletes it in `finally`, including after OCR
  errors and timeouts. Cancellation produces no alarming failure notification.
  This is ordinary unlinking, not guaranteed erasure, and a forced process
  termination or machine crash can leave the file behind.
  [Temporary-file lifecycle](https://github.com/nix-forge/nix-conf/blob/9d39e12d9a394c6459e98f3b58d08f8069723710/modules/home/macos/ocr_capture.py#L336-L376)
- The cleanup code recognizes common list markers and tries not to flatten URLs
  or code-shaped lines. It is small and inspectable.
- The helper has explicit permission guidance, a bounded OCR subprocess, empty
  result feedback, and success feedback that reveals only a character count.
- The worktree test calls the installed-style helper interface instead of only
  importing an internal function. That is a useful start. [Current OCR cleanup
  test](../tests/macos/test_home_helpers.py#L78-L105)

### Gaps that matter most

#### 1. Capture and permission do not share an identity

The Swift engine calls `CGPreflightScreenCaptureAccess`, then Python starts
`/usr/sbin/screencapture` to obtain the PNG. A successful preflight proves that
the engine may capture; it does not prove that the child command will present
or complete its selector. This is the failure pattern Vorssaint documents in
its own source. [Current preflight](https://github.com/nix-forge/nix-conf/blob/9d39e12d9a394c6459e98f3b58d08f8069723710/modules/home/macos/ocr_capture.py#L124-L143)
[Current external capture](https://github.com/nix-forge/nix-conf/blob/9d39e12d9a394c6459e98f3b58d08f8069723710/modules/home/macos/ocr_capture.py#L92-L109)

There is a second identity problem at rebuild time. The Nix derivation sets a
code-signing identifier, but it signs with the ad-hoc identity `-`. The built
binary's actual designated requirement is its exact CDHash, not the textual
identifier. Apple says an ad-hoc designated requirement is tied to that version
of the code, so macOS cannot reliably carry privacy permission to the next
build. [Current ad-hoc signing](../modules/home/macos/ocr-capture.nix#L39-L45)
[Apple code-signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

Use one signed native process for both operations. ScreenCaptureKit can return a
cropped `CGImage` directly, so the process can pass memory to Vision without an
intermediate PNG. This also gives the selection UI one stable owner for
permission text, focus, cancellation, notifications, and accessibility. Package
it as an app bundle and sign it with a stable Apple Development or Developer ID
identity if Screen Recording approval must survive code changes. A stable path
and bundle identifier do not, by themselves, make an ad-hoc signature stable.

#### 2. The output renderer guesses too much and offers no true raw mode

The Swift comparator decides whether two observations share a row separately
for each pair, based on their heights. That is not stable row clustering, and
multi-column layouts can interleave. The Python "balanced" pass then joins
lines using punctuation heuristics. Even "minimal" applies NFKC, strips every
line, and removes blank lines. It cannot return Vision's literal output.
[Current ordering](https://github.com/nix-forge/nix-conf/blob/9d39e12d9a394c6459e98f3b58d08f8069723710/modules/home/macos/ocr_capture.swift#L84-L130)
[Current cleanup](https://github.com/nix-forge/nix-conf/blob/9d39e12d9a394c6459e98f3b58d08f8069723710/modules/home/macos/ocr_capture.py#L235-L324)

Keep structured observations until the last step. Each item should carry text,
confidence, bounding box, candidate rank, and language when the API provides
it. Then offer explicit renderers:

- `raw`, with only newline normalization;
- `lines`, preserving Vision's observations;
- `paragraph`, with script-aware joining;
- `code`, preserving whitespace and punctuation;
- `table`, using document structure where available and geometric fallback
  elsewhere.

Apple exposes candidate confidence and bounding geometry, so an optional review
surface can mark uncertain text without changing the one-shot default. [Apple
recognized-text result](https://developer.apple.com/documentation/vision/vnrecognizedtext)

#### 3. Failure handling is incomplete

`_ensure_screen_capture_permission` treats every nonzero preflight exit as a
permission denial. A missing or crashing engine therefore produces the wrong
advice. `pbcopy` uses `check=True`, but `CalledProcessError` is not an
`OCRCaptureError`, so a clipboard failure escapes as a traceback rather than a
notification. The capture and preflight subprocesses have no noninteractive
timeout. Vision's 120-second limit prevents an endless OCR child, but it is too
long for a quick desktop action and supplies no progress or cancel control.
[Permission classification](https://github.com/nix-forge/nix-conf/blob/9d39e12d9a394c6459e98f3b58d08f8069723710/modules/home/macos/ocr_capture.py#L124-L143)
[OCR timeout](https://github.com/nix-forge/nix-conf/blob/9d39e12d9a394c6459e98f3b58d08f8069723710/modules/home/macos/ocr_capture.py#L146-L173)
[Clipboard write](https://github.com/nix-forge/nix-conf/blob/9d39e12d9a394c6459e98f3b58d08f8069723710/modules/home/macos/ocr_capture.py#L327-L333)

Define distinct capture, permission, decode, OCR, timeout, and clipboard error
states. Preserve the underlying error in logs while showing a short recovery
action. Show progress only when work exceeds a small threshold. A native
`VNRequest` can be cancelled; killing an outer subprocess after two minutes is
not equivalent. [Apple `VNRequest`
cancellation](https://developer.apple.com/documentation/vision/vnrequest)

#### 4. Work is not bounded by image size or concurrent invocation

There is no pixel-count or dimension ceiling, adaptive downscale, or minimum
text-height policy. A large Retina selection can consume much more memory than
a typical region. Apple documents that increasing `minimumTextHeight` reduces
memory and recognition time by ignoring small text. PowerToys also avoids its
1.5 scale-up when it would exceed the platform OCR dimension limit. [Apple
minimum text height](https://developer.apple.com/documentation/vision/vnrecognizetextrequest/minimumtextheight)

AeroSpace starts the helper with `exec-and-forget`. Multiple key presses can
start overlapping Python processes and system selectors; there is no session
lock or request generation shared between them. [AeroSpace
binding](../modules/home/macos/ocr-capture.nix#L130-L137)

Add a single-session guard. In the native design, a second invocation can focus
the active selector or cancel it by policy. Put a hard pixel budget before OCR,
downscale oversized captures, and test a small-text preset separately from the
ordinary fast path.

One small local fixture confirms that the recognition-level option has a real
quality tradeoff. On this Mac, five separate accurate runs over a 1000 by 220
pixel, three-line image took 0.23 to 0.27 seconds each and reproduced every
character. Five fast runs took 0.09 seconds each, but the URL was corrupted and
an extra blank line appeared. This is a directional microbenchmark, not an
end-to-end latency claim: it excludes interactive selection, PNG encoding,
Python startup, pasteboard output, and notification. It supports keeping
accurate as the default and treating fast as an explicit low-latency choice.

#### 5. The interaction is fast but almost invisible

The system selector is familiar, yet it cannot show the active OCR language,
output mode, OCR purpose, last region, confidence, or recognized result. There
is no retry action when Vision finds nothing and no editable review before the
clipboard is overwritten. The only launch integration is an AeroSpace binding;
if AeroSpace is disabled, the package remains callable from a shell but has no
desktop trigger.

Keep direct copy as the default, but give region copy, window copy, and editable
review distinct shortcuts. Each selection overlay should do one job and show
only the frozen desktop, selection, and a compact size or window label. Put
language and output policy in declarative configuration, not under the pointer.
On success, use short passive feedback without controls; Apple recommends HUD
panels only for small transient information and advises against putting controls
in them. Put copy, save, speech, and code review in a normal customizable toolbar
inside the review window. A review window should expose selectable text and
bounding boxes to VoiceOver. Optional text-to-speech is a useful accessibility
destination. [Apple panel guidance](https://developer.apple.com/design/human-interface-guidelines/panels)

The native implementation also needs an explicit Retina boundary. `SCDisplay`
dimensions are points, while screenshot configuration dimensions are pixels;
the exact conversion comes from `SCContentFilter.pointPixelScale`. Requesting
point counts as pixel counts produces a half-resolution capture on a 2× display.
AppKit views should draw the resulting image in their native coordinate system
without applying an additional Core Graphics vertical flip. [Apple `SCDisplay`](https://developer.apple.com/documentation/screencapturekit/scdisplay)
[Apple screenshot width](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/width)
[Apple point-to-pixel scale](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/pointpixelscale)

#### 6. Clipboard and history policy need an explicit privacy decision

The capture PNG is short-lived, but recognized text stays on the general
pasteboard until another owner replaces it. Any enabled clipboard manager may
copy it into its own history. The general pasteboard also participates in
Universal Clipboard unless the writer opts out. That is normal pasteboard
behavior, but a tool advertised as private should say so. [Apple general
pasteboard](https://developer.apple.com/documentation/appkit/nspasteboard)

Use AppKit's `currentHostOnly` option by default so OCR output does not travel to
other devices. Offer an optional auto-clear delay that clears only if this tool
still owns the same pasteboard generation. AppKit's `changeCount` exists for
exactly that ownership check. [Apple current-device-only
pasteboard](https://developer.apple.com/documentation/appkit/nspasteboard/contentsoptions/currenthostonly)
[Apple pasteboard change
count](https://developer.apple.com/documentation/appkit/nspasteboard/changecount)

Do not add history as a silent default. If history is wanted, make it visibly
opt-in, bounded by count and age, easy to clear, and able to omit thumbnails.
The UI should state its directory and retention rule. Avoid copying TRex's
plain JSON plus JPEG design without an at-rest protection decision.

#### 7. Tests cover one narrow happy path

The current OCR test checks one balanced-cleanup example. There are no tests for
the Swift argument parser, supported and unsupported languages, geometric
ordering, right-to-left or CJK text, low confidence, empty results, cancellation,
timeouts, clipboard errors, duplicate invocation, or permission-state
classification.

Add a fixture corpus with expected raw and rendered outputs. Include small text,
Retina captures, columns, tables, source code, URLs, bullets, mixed scripts,
right-to-left text, and deliberately blank images. Record wall time and peak
memory for each fixture in accurate and fast modes. Tests should verify bounds
and regressions, not promise a universal accuracy percentage.

## Recommended target design

| Stage | Recommended responsibility |
| --- | --- |
| Invocation | One native executable with `capture`, `image`, `stdin`, `languages`, and `diagnose` commands. Give region copy, window copy, and editable review distinct AeroSpace shortcuts, with optional menu bar or Shortcuts integration. Enforce one active capture session while forwarding each new invocation's arguments. |
| Selection | AppKit overlay backed by ScreenCaptureKit. Keep in-memory images, exclude the overlay, support all displays and backing scales, freeze by default, and provide Escape, move, repeat-last-region, keyboard focus, and accessibility labels. |
| Recognition | A cancellable background Vision request. Validate requested languages against the selected recognition level and Vision revision. Support custom words, a bounded small-text preset, explicit orientation for file input, and a hard pixel budget. |
| Result model | Retain text candidates, confidence, bounding geometry, and language metadata. Do not reduce to strings before ordering and rendering. |
| Rendering | Raw, lines, paragraph, code, and table profiles. Keep transformations reversible where possible and preview lossy cleanup before replacing raw output. |
| Output | Clipboard by default. Add stdout, append, file, editable review, and text-to-speech as explicit destinations. QR content must be reviewed before opening, with a strict scheme allowlist. |
| Privacy | No network path in the baseline. No screenshot file for normal capture. Pasteboard output is current-device-only by default; optional expiry uses ownership checking. History is off by default and has count, age, thumbnail, and clear-all controls. |
| Feedback | Separate cancelled, permission denied, capture failed, no text, OCR failed, timed out, and clipboard failed. Show a delayed progress state and let Escape cancel recognition. |

On macOS 26 and later, Apple's `RecognizeDocumentsRequest` can provide document
structure rather than forcing the app to reconstruct every relationship from
line boxes. Apple exposes paragraphs, lines, words, lists, tables, and barcodes,
and its table sample exports structured data. Use that path behind an
availability check, with the existing text request as the compatibility path.
[Apple document-recognition
API](https://developer.apple.com/documentation/vision/recognizedocumentsrequest)
[Apple table-recognition
sample](https://developer.apple.com/documentation/vision/recognize-tables-within-a-document)

## Implementation order

1. Replace external `screencapture` plus temporary PNG with one native,
   ScreenCaptureKit-backed app bundle with a stable signing identity. Add
   single-session handling, typed errors, a hard image bound, current-device-only
   clipboard output, and clipboard error handling at the same time.
2. Introduce a structured OCR result and deterministic row/column clustering.
   Add literal raw, lines, paragraph, and code output profiles. Validate
   languages using Vision's supported-language query.
3. Add an optional review window with confidence, bounding boxes, a native
   customizable toolbar, and keyboard or VoiceOver access. Keep direct copy as
   the default and make its confirmation passive and short-lived.
4. Add custom words, adaptive small-text preprocessing, and fixture-based
   accuracy, latency, and memory tests. Do not enable preprocessing globally
   until those measurements show a win.
5. Add advanced workflows only after the core is stable: QR review, multi-region
   capture, table export on macOS 26, stdout and file input, repeated last-region
   capture, text-to-speech, and opt-in bounded history.

The first two steps fix correctness and reliability. The later steps make the
tool feature rich without turning every quick copy into an editor session.
