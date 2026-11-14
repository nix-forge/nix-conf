# Readable captions in Moonfin, Jellyfin and mpv

Reviewed: 2026-10-04. Scope: Moonfin Core 2.6.0 at
`b86bbe6021eff5befdf311134bf3e831c032f21f`, Moonbase 2.3.0.0 at
`e2dea919efaf9d226853ee708a50830af5e69daa`, Jellyfin Web 12.1, and mpv 0.41.0.

## Answer

Use compact white sans-serif text with a black outline and transparent backing
for plain-text subtitles. Preserve authored ASS/SSA styling and embedded fonts,
including anime signs, songs and positioned dialogue. A black background remains
an optional contrast aid. The 2026-10-04 revision replaces the previous large,
bold, boxed default after it proved too intrusive for the viewer.

Subtitle format determines what can be preserved. Anime can contain SRT with no
authored typography, and films or other television can contain styled ASS.
Do not force an anime-specific font over all tracks or infer typesetting from
genre alone.
The configured sizes are starting points, not an accessibility certification.
Viewing distance, screen size and eyesight matter. Consistency means comparable
readability and controls; forcing every subtitle format into one visual style
would damage some tracks.

## Findings and sources

- [Apple TV caption settings](https://support.apple.com/guide/tv/turn-closed-captions-sdh-apple-tv-4k-atvb1d61ca06/tvos)
  expose font, size, color, background opacity and edge controls. Apple does not
  specify one universal numerical preset. Its
  [accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility)
  supports viewer customization. These settings guide this design; they do not
  automatically control Moonfin's custom renderer.
- [W3C media accessibility requirements](https://www.w3.org/TR/media-accessibility-reqs/)
  warn in CC-12 that white text with shadows can disappear against bright imagery.
  A local black background supplies contrast without covering the whole width.
  The chosen 75% opacity is an implementation choice, not an Apple or W3C rule.
  Under conventional sRGB compositing, white text against that backing over white
  footage has roughly 13:1 contrast. This does not certify HDR output.
- The [Netflix general timed-text guide](https://partnerhelp.netflixstudios.com/hc/en-us/articles/215758617-Timed-Text-Style-Guide-General-Requirements)
  specifies white proportional sans-serif text and resolution-relative sizing.
  Its [English guide](https://partnerhelp.netflixstudios.com/hc/en-us/articles/217350977-English-USA-Timed-Text-Style-Guide)
  addresses line breaking and positioning around important picture content.
  These are authoring guides. Player styling cannot correct transcription,
  missing dialogue, timing or every authored line break.
- The [BBC subtitle-size research](https://bbc.github.io/gaad/how_big_should_subtitles_be/index.html)
  explains the effect of device size and viewing distance. Its line-height
  measurements are not interchangeable with an mpv font-size percentage.
  Adjustable sizing is more defensible than claiming one size fits every screen.
- The [mpv subtitle manual](https://mpv.io/manual/stable/#subtitles) documents
  reference-height font sizing, outline and background controls, embedded fonts,
  and ASS overrides. `sub-ass-override=no` protects authored layout; bitmap
  subtitles have their own scaling behavior. Burned-in text is part of the video
  and cannot be restyled by a caption preference.
- [Moonfin's native backend](https://github.com/Moonfin-Client/Moonfin-Core/blob/b86bbe6021eff5befdf311134bf3e831c032f21f/lib/playback/media_kit_player_backend.dart)
  converts size 24 to mpv size 55 at a reference height of 720, and a 0.04 offset
  to a 29-unit bottom margin. It supplies a two-unit outline and treats weight
  700 or above as bold. ASS/SSA Direct Play selects `sub-ass-override=no`.
  Its custom mpv configuration allowlist excludes subtitle controls, so a
  standalone `mpv.conf` cannot configure Moonfin's captions.
- [Moonfin preferences](https://github.com/Moonfin-Client/Moonfin-Core/blob/b86bbe6021eff5befdf311134bf3e831c032f21f/lib/preference/user_preferences.dart)
  scope appearance by account and server.
  [Synced fields](https://github.com/Moonfin-Client/Moonfin-Core/blob/b86bbe6021eff5befdf311134bf3e831c032f21f/lib/data/services/synced_fields.dart)
  carry those settings to Moonbase. The
  [Moonbase API](https://github.com/Moonfin-Client/Plugin/blob/e2dea919efaf9d226853ee708a50830af5e69daa/Jellyfin/backend/Api/MoonfinController.cs)
  accepts a partial settings envelope for a managed user. Its
  [merge implementation](https://github.com/Moonfin-Client/Plugin/blob/e2dea919efaf9d226853ee708a50830af5e69daa/Jellyfin/backend/Services/MoonfinSettingsService.cs)
  retains unrelated profile fields.
- Moonfin's unmodified Linux backend writes `sub-back-color` without enabling
  a box. The registered temporary fix sets `sub-border-style=background-box` for
  nontransparent backgrounds and uses a four-unit padding. Transparent backgrounds
  restore outline mode and remove padding. ASS direct play remains enabled.
  Its package version and exact source revision require review before an update.
- [Moonfin's Apple overlay](https://github.com/Moonfin-Client/Moonfin-Core/blob/b86bbe6021eff5befdf311134bf3e831c032f21f/tvos/Runner/Playback/Aether/SubtitleOverlay.swift)
  already supports attributed-string backgrounds. Its size reference is 1080,
  whereas mpv uses 720; identical sliders do not produce identical apparent sizes.
  The signed macOS package remains unmodified. Native Apple, Android and browser
  backends support these preferences, but each renderer has different metrics.
- [Jellyfin Web settings](https://github.com/jellyfin/jellyfin-web/blob/v12.1/src/scripts/settings/userSettings.js)
  store subtitle appearance locally under `localplayersubtitleappearance3`,
  explicitly bypassing server display preferences. The
  [appearance helper](https://github.com/jellyfin/jellyfin-web/blob/v12.1/src/components/subtitlesettings/subtitleappearancehelper.js)
  maps medium text to 1.36em and Uniform to a black outline. A package default
  preserves the native dialog; forced server CSS would compete with its controls.

## Implemented configuration

| Player | Ordinary text baseline | Adjustment and preservation |
| --- | --- | --- |
| Moonfin desktop | Size 18, regular white text, black outline, transparent background, 4% offset | Native subtitle customization and account sync; ASS/SSA Direct Play stays enabled |
| Moonfin global / mobile / TV profiles | Size 18 / 18 / 20 with the same colors and offset | Device profiles retain separate size controls; actual rendering depends on the client |
| Jellyfin browser | Medium regular sans-serif, white, Uniform black edge, transparent background | Existing browser choices win over the package default; position and bitmap aspect defaults remain upstream |
| Standalone mpv | Noto Sans, regular size 41 at reference height 720, two-unit black outline, transparent backing, 28-unit bottom margin | Keyboard presets and size/position controls; authored ASS and embedded fonts preserved |

The [Moonfin setup module](../../hosts/nixos/desktop/local/homelab/captions.nix) installs
an authenticated, loopback-only setup service. It applies each explicit preset revision once to the
managed administrator and viewer accounts. A private marker per server and user
prevents later boots from overwriting GUI choices. It merges only caption fields
and logs out its API session. Disabled account synchronization is an error, not
permission to turn synchronization on. The client must also have settings sync
enabled to receive the preset.

The [Jellyfin overlay](../../pkgs/pkgs/by-name/je/jellyfin-web-personal/package.nix) changes native
appearance defaults. A separately registered temporary fix stops upstream reads
from mutating the shared defaults when switching accounts. Existing saved browser
appearances are intentionally retained.
Use the appearance dialog to select the baseline below if a browser already has
custom settings. The server does not receive or overwrite that browser-local state.
This overlay affects the Jellyfin web bundle served by this server, not unrelated
servers or third-party clients.

The [mpv module](../../modules/home/mpv/default.nix) owns its media styling rather than
Stylix's mpv target. This also leaves mpv's OSD outside the desktop palette.
English language preference and matching sidecar discovery apply to standalone mpv.
Existing Jellyfin language selection, subtitle acquisition and extraction remain
owned by the media service configuration.

## Adjust while watching

In Moonfin, open Settings, Subtitles, then Subtitle Customization. Increase text
size for couch viewing or small screens. The initial weight is Normal and the
background is transparent. Select a black background through the native controls
when additional contrast is needed. Keep
ASS/SSA Direct Play enabled for anime. Turning it off allows a uniform override
but can change sign placement and typography. Separate HDR subtitle appearance is
available in Moonfin; this preset leaves it unchanged until tested on the actual
HDR display. Grey text may help if captions appear too bright.

In Jellyfin's user settings, open Subtitles and the appearance controls. Select
Medium, Normal, white text, Uniform edge, and None for a transparent background
for the baseline. The package exposes the previously hidden background field as
a selector with transparent, 50%, 75% and opaque choices. Existing custom colors
remain selectable when changing other appearance settings. Use Normal weight or a smaller size when preferred.
Each browser/device keeps its own selection. Keep subtitle burn-in on Auto rather
than forcing all text to be burned into video. ASS and bitmap playback depend on
the browser, codec and selected track; text appearance controls do not restyle
rasterized or burned-in captions.

Standalone mpv controls:

| Shortcut | Action |
| --- | --- |
| `Alt+1` | Restore balanced appearance, scale and position; preserve ASS styling |
| `Alt+2` | Use opaque black backing for maximum contrast |
| `Alt+4` | Switch ordinary text to outline only |
| `Alt+3` | Toggle forcing the player style onto ASS; use only when needed |
| `Alt+=` / `Alt+-` | Increase / decrease subtitle scale |
| `Alt+Up` / `Alt+Down` | Move subtitles upward / downward |
| `j` / `J` | Next / previous subtitle track |
| `v` | Toggle subtitle visibility |
| `z` / `x` | Adjust subtitle timing |

Position and scaling adjustments can also affect authored tracks. `Alt+1` restores
the baseline. Interactive mpv changes last for that process; edit its Home Manager
configuration to make a different baseline permanent.

For a poorly styled ASS dialogue track, prefer a suitable SRT alternative when
available, or use the explicit override temporarily. A forced-signs-only track
will not supply full dialogue. SDH tracks include sound and speaker information;
choose them when that information is needed. Styling cannot add missing content.

## Deployment and validation

Changes take effect after the normal reviewed system and home activation. The
server setup unit is `homelab-caption-setup.service`. After activation, let Moonfin
sync or reopen it, and reload Jellyfin's web client to obtain the new bundle.
Do not clear browser storage merely to apply captions, because it holds other
preferences. Select the appearance values in its dialog instead.

The v2 migration applies this requested readability revision even when a v1
marker exists. Once v2 succeeds, later restarts preserve GUI changes. To reapply
it deliberately, remove only the intended user's `*-v2` marker from the private
`homelab-captions` state directory, then restart the setup unit. Back up previous
choices first. Never remove every account's markers as routine maintenance.

Validation on Linux:

- Five HTTP fixture tests passed for one-time provisioning, retry after a rejected
  write, preserving disabled synchronization, refusing redirects, and migrating
  an earlier preset exactly once.
- The account-switch regression failed against unmodified Jellyfin Web 12.1 and
  passed in the patched package's build. The final web bundle and setup service
  built successfully. Jellyfin's evaluated wrapper selects that exact bundle.
- The temporary-fix registry check passed, including its platform evaluations.
- Both desktop Linux and macOS mpv configurations evaluated successfully. The
  installed Linux mpv 0.41.0 parsed the generated Home Manager config and bindings;
  IPC checks verified subtitle properties. A synthetic two-line SRT rendered
  through mpv/libass against white footage showed compact dark backing and clear
  white glyphs while ASS overrides stayed disabled. A detailed color test pattern
  remained readable, and authored ASS frames were byte-identical with the plain
  background enabled and disabled. This used software X11 output;
  a software OpenGL attempt rendered the video incorrectly and was discarded.
- Ruff, Python type checks, Nix formatting, JavaScript lint and formatting,
  Markdown checks, local
  documentation links, whitespace and the publication secret scan passed.

The first evaluation exposed Stylix's competing subtitle font assignment; the
module now gives media styling one owner. A superseded web build was cancelled
before the corrected build passed. Type checking needs the pinned test Python
environment because the default environment does not include pytest.

The earlier v1 deployment on desktop Linux completed after its implementation checks.
The first live API check exposed that Jellyfin prioritizes the Authorization
header over a separate token header. The client now includes its token in that
same Authorization header. The strengthened regression test failed before this
correction and all four tests passed afterward.

During v1 deployment, a full desktop build passed, but its activation preview included unrelated
pending service changes. The deployed system was instead built from the active
system's saved source plus the caption changes. Its activation passed, including
Home Manager and the caption setup service. Existing account settings were backed
up privately before provisioning. Authenticated reads verified the saved preset
in all four Moonfin profiles for both managed accounts. The live web bundle's
checksum matched the patched build, and mpv's installed config and shortcuts
matched the caption settings. Jellyfin reported Healthy, and no system units were
failed after activation.

Real movie playback, HDR output, native macOS playback and Apple TV controls
remain unverified. Check a bright scene, a dark scene, two-line dialogue,
letterboxed film, positioned ASS signs, and a bitmap track. Then change size in
each GUI and reopen the client to verify persistence. No caption preset can
guarantee identical rendering across those backends.

The v2 checks additionally exercised the real Moonfin Dart style writer against
an observable native-property channel. Unmodified upstream failed with a missing
box; the patch passed background, transparent reset, padding, alpha, weight and
ASS-preservation checks. Jellyfin's actual form loader and serializer preserved
all four background choices and an existing custom color.

On macOS, the mpv home generation built successfully. A whole-home dry activation
found unrelated generation drift and secret-cache readiness failures, so it was
not activated. Only the generated mpv configuration and keyboard binding symlinks
were installed, with their previous links retained privately. The installed macOS mpv accepted the new configuration, and Noto Sans was
present in the managed font directory. The source module contains the same
changes for the next normal system activation. This does not
constitute a full Darwin system deployment.

A standalone browser cue experiment did not reproduce Jellyfin's full player
layout, so it is not evidence of Jellyfin's apparent text size. Browser validation
here covers the native settings form and generated bundle; visual checks of the
full authenticated player remain outstanding.

Build the desktop closure through its workload runner with one local build job
when rebuilding both Flutter and Jellyfin Web:

```sh
just os-build desktop -- --max-jobs 1 --cores 2
```

The initial concurrent v2 build was cancelled after sustained memory pressure.
Serial execution cleared that pressure without changing the host's memory policy.

The temporary-fix checks passed across the root's three supported platforms after
restricting the Moonfin workaround to x86-64 Linux. The first broader check caught
an attempt to select Moonfin on aarch64 Linux, where the package is unavailable.
The signed Darwin package remains unchanged.

The final v2 desktop closure built and activated successfully from the active
system's saved source plus the caption changes. The activation preview required
Jellyfin and Home Manager refreshes. The caption setup service was explicitly
started after activation to apply v2 to existing accounts. Private backups were
retained before migration.

Authenticated reads verified every configured field in all four profiles for
both managed accounts. Other fields in those profiles matched their backups.
The live Jellyfin default and subtitle-settings bundles matched the built files
by SHA-256, including the visible background selector. Jellyfin reported Healthy
and no system units were failed. The installed patched Moonfin executable was
selected by the desktop profile. Installed mpv IPC checks passed on Linux and
macOS for font, size, ASS preservation and transitions between outline, opaque
and translucent presets, including resetting box padding.

Restart Moonfin to load the rebuilt Linux player and let client settings sync
receive the revised profile. Reload Jellyfin to load its new web client. Saved
browser appearance overrides still take priority; use the now-visible background
selector to choose Black, 75% opacity when a browser has an older custom style.

## Rounded backgrounds and resolution

The [rendering patch](../../pkgs/pkgs/by-name/je/jellyfin-web-personal/jellyfin-caption-rendering.patch)
adds a `0.18em` corner radius and compact proportional padding to Jellyfin's
HTML caption boxes and appearance previews. Native WebVTT cues stay square:
[the WebVTT cue styling specification](https://www.w3.org/TR/webvtt1/#the-cue-pseudo-element)
does not include `border-radius` among its supported properties. mpv 0.41 and
Moonfin's current subtitle preferences have no supported corner-radius setting.
Changing subtitle renderers solely for rounded corners could lose positioning,
ASS features or native picture-in-picture behavior, so renderer selection stays
unchanged. The appearance preview can therefore have rounder corners than native
playback.

Ordinary Jellyfin text now uses `max(1rem, 2.5vmin)` as its base size in both the
HTML renderer and native cue styling. The existing size choices multiply that
base; Large uses 1.72. A 1920-by-1080 CSS viewport therefore uses a 46.44px font,
and a 3840-by-2160 viewport uses 92.88px. At device pixel ratio 2, a 1080-height
CSS viewport draws the same relative size using twice as many physical pixels.
The rem floor keeps small windows legible. These are chosen defaults, not values
mandated by Apple. Viewer size and font controls remain available.

Jellyfin's ASS renderer now uses `prescaleFactor: 1.0`, retaining the existing
2160 render-height ceiling. The
[SubtitlesOctopus options](https://github.com/libass/JavascriptSubtitlesOctopus#usage)
explain that a factor below one trades canvas resolution for performance.
This removes the previous 0.8 reduction where it applied, without replacing
anime typography or animations. Full-resolution rendering can cost more GPU or
CPU time on slower clients. Bitmap subtitles and text already burned into video
cannot acquire new detail from this change.

[mpv's window scaling options](https://mpv.io/manual/stable/#options-sub-scale-by-window)
already size ordinary text from the output window, with vector glyphs rendered
at the output resolution. They remain enabled. Authored ASS retains its own
coordinate system and fonts.

A Chromium fixture using the patched player CSS and actual appearance helper
confirmed proportional font sizes, padding and corner radii at 1080p, 2160p and
1080 CSS pixels with device pixel ratio 2. All six size choices produced accepted
native-cue CSS. Native cues also rendered in a synthetic video fixture. These
checks exercise the renderer styles, not authenticated Jellyfin playback, HDR,
Safari or every television browser.

The installed Linux mpv rendered the same synthetic SRT at output sizes
1920-by-1080 and 3840-by-2160 with window scaling enabled and ASS overrides
disabled. A first capture ran before video initialization and failed; waiting for
initialization produced both output-sized screenshots. Inspection confirmed
readable text and proportional backing.

The rounded-caption desktop build passed. A concurrent system activation had
already installed the same web package, so the older prepared system was not
activated over it. SHA-256 comparisons confirmed that the live player JavaScript,
HTML-caption stylesheet and appearance-preview stylesheet matched the built
files, including responsive cue sizing, rounded HTML boxes and full-resolution
ASS settings. Jellyfin reported Healthy and no system units were failed.
Reload the web client to receive these changes; existing appearance choices remain
in effect.

## Compact plain-text revision

Moonfin converts its size slider to mpv reference units with
`round(size / 24 * 55)`. The previous desktop setting 24 therefore produced 55,
larger than standalone mpv's previous 46. The compact desktop default now uses
Moonfin 18 and mpv 41. The TV profile starts at 20 for viewing distance; all
profiles retain size controls. Jellyfin Medium multiplies its viewport-relative
base by 1.36, giving 36.72 CSS pixels at a 1080-height landscape viewport and
73.44 at 2160. Regular weight and transparent backing reduce visual coverage.
These sizes reflect viewer preference, not a universal accessibility standard.

The pinned [Moonfin native backend](https://github.com/Moonfin-Client/Moonfin-Core/blob/b86bbe6021eff5befdf311134bf3e831c032f21f/lib/playback/media_kit_player_backend.dart)
uses ASS Direct Play to set `sub-ass-override=no`. Its native path keeps authored
ASS independent of the plain-text size and background. The embedded-style toggles
also remain enabled for backends that use them. The
[track-selection logic](https://github.com/Moonfin-Client/Moonfin-Core/blob/b86bbe6021eff5befdf311134bf3e831c032f21f/lib/util/subtitle_track_logic.dart)
retains an explicit or active track before format ranking. Enabling ASS does not
replace a remembered SRT selection. Select the full-dialogue ASS track when
available; a signs-only track is not a dialogue replacement. Plain SRT cannot
reconstruct absent sign positioning or authored fonts.

The v3 migration changes only values still matching the managed v2 preset.
Later viewer adjustments and unrelated settings survive. Its HTTP regression
failed before the migration change and all six provisioning tests passed after
it. Browser-local choices remain authoritative; select the compact values in
the appearance dialog if a browser retains the old large boxed style.

Synthetic plain-text captures rendered at 1080p and 4K with output-window
scaling enabled. An authored ASS fixture with positioned styling produced
byte-identical screenshots before and after the plain-text revision. This
checks style isolation, not every real anime track. No active Moonfin session
was available during this inspection, so the reported episode's actual selected
track and delivery path remain unconfirmed pending viewer details.

Transparent backing removes the unwanted square block. It does not add rounded
boxes to Moonfin or native browser cues: those renderer limitations still apply.
Jellyfin HTML backgrounds remain rounded when a nontransparent background is
selected. `Alt+2` in standalone mpv retains the opaque contrast option.

The v3 desktop closure built and activated from the prior active source plus
caption changes. The macOS home generation built; only its generated mpv config
and bindings were installed, with rollback links retained. Installed mpv property
and preset-transition checks passed on both platforms. Authenticated verification
confirmed the saved compact preset in all four Moonfin profiles for both managed
accounts and unchanged unrelated fields. The served browser defaults matched the
built JavaScript by SHA-256. Jellyfin reported Healthy; no system units failed.
The package repository's all-system evaluation check passed. The scoped desktop
build used the equivalent pre-move overlay because the checkout's concurrent
package-layout migration was outside this deployment.

Browser fixtures confirmed the compact font scales from 36.72 to 73.44 CSS
pixels between 1080- and 2160-height viewports and handles device pixel ratio 2.
Real movie playback, the reported anime episode, HDR and native Apple subtitle
rendering still need viewer confirmation. Reopen Moonfin to sync, and reload
Jellyfin. Saved browser-local overrides may require selecting the compact values
in the appearance dialog.

## Native Apple limits and official app

The pinned Moonfin [Apple subtitle overlay](https://github.com/Moonfin-Client/Moonfin-Core/blob/b86bbe6021eff5befdf311134bf3e831c032f21f/tvos/Runner/Playback/Aether/SubtitleOverlay.swift) uses the system font and does not expose font-family or outline-width controls for ordinary text. Standalone mpv preferences do not reach that renderer. Anime SRT tracks have no embedded typeface to preserve; authored ASS can carry fonts, signs, and positioning. This explains why a style setting cannot restore typesetting that is absent from the selected track.

A local patched macOS app was built during investigation but was removed at the viewer's request. The official upstream Developer ID signed Moonfin bundle was restored and verified. The configuration no longer installs or restores a custom app. Moonfin, Jellyfin in a browser, and other clients share subtitle availability through Jellyfin's library and adjacent sidecar files, but each client retains its own rendering controls.

## Subtitle acquisition and coverage

[Bazarr's language guide](https://wiki.bazarr.media/Additional-Configuration/Settings/Languages/) distinguishes default profiles for new items from profiles already assigned to existing items. Its [provider guide](https://wiki.bazarr.media/Additional-Configuration/Settings/Providers/) recommends more than one provider. The installed [YIFY provider](https://github.com/morpheus65535/bazarr/blob/v1.6.2/custom_libs/subliminal_patch/providers/yifysubtitles.py) supports movies only, so the former provider list left external TV subtitles dependent on SubtitleCat.

A library audit found one monitored anime series with the intended anime profile and one movie with the English profile. Eight consecutive episodes had no English track in the video; the earlier episodes did. Bazarr correctly listed English as missing. A manual search with the former providers returned no candidates. The installed Bazarr 1.6.2 [TsukiHime provider](https://github.com/morpheus65535/bazarr/blob/v1.6.2/custom_libs/subliminal_patch/providers/tsukihime.py) returned multiple English candidates for a representative missing anime episode without an account. It is now in the declared provider list. Its first selected ASS sidecar contained full dialogue and spanned the video's runtime. The anime profile preserves the provider's original format so authored ASS styling is not flattened to plain text.

Bazarr's ordinary missing-subtitle search filled six more episodes with English hearing-impaired SRT tracks. A manual match review found non-hearing-impaired English ASS alternatives at a stronger release match score. Those authored tracks were downloaded in their original format, and the SDH files were retained as accessible alternatives. The ASS files contain dialogue across the video's runtime, though match scores and cue bounds do not prove cue-by-cue synchronization. One more episode returned no candidates from the account-free providers. The installed [Bazarr SubDL provider](https://github.com/morpheus65535/bazarr/blob/v1.6.2/custom_libs/subliminal_patch/providers/subdl.py) requires an API key. [SubDL documents a free personal key](https://subdl.com/developers) and Bazarr integration. A personal free key was validated, encrypted with nix-seal, and supplied to Bazarr at runtime. The provider then returned one full-English candidate with a strong match score; Bazarr downloaded its ASS track and indexed it. [OpenSubtitles.com](https://blog.opensubtitles.com/opensubtitles/web/understanding-opensubtitles-websites-and-services) remains a possible second account-backed source for broader TV and movie coverage if measured gaps remain. Availability on a website alone does not prove that Bazarr's API search will rank or download the same file.

Jellyfin [recognizes language-coded sidecars](https://jellyfin.org/docs/general/server/media/shows/) beside media files. Its media-stream API listed the new tracks after library scanning and item refreshes. For the upgraded episodes, it lists the non-SDH ASS track first and the SDH SRT alternative second. The last sidecar also appeared as an external English ASS track after an item refresh. The installed Bazarr version supports [Jellyfin refresh integration](https://wiki.bazarr.media/Additional-Configuration/Jellyfin/); enabling this with a dedicated key may remove that refresh delay, but the existing watcher already discovers sidecars. Bazarr remains the sole automatic subtitle writer. The full desktop closure built and activated; Bazarr integration reconciled successfully with both providers and the sealed SubDL key. Playback timing was checked against runtime and cue bounds, but cue-by-cue sync and every client display mode still require viewer confirmation.

## iOS client release gap

Checked 2026-10-06. The native iOS app observed by Jellyfin reports Moonfin 2.5.1. The [Apple App Store listing](https://apps.apple.com/app/moonfin/id6761283970) also lists 2.5.1, while the [upstream 2.6.0 release](https://github.com/Moonfin-Client/Moonfin-Core/releases/tag/2.6.0) fixes embedded ASS fonts reaching libass on Apple platforms. A server deployment cannot update an App Store client's native renderer. Moonfin's [installation guide](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Installation) recommends the App Store for iOS; its release IPA needs separate signing.

The running Moonbase API reports settings synchronization enabled for the managed accounts. Both stored and resolved mobile profiles retain the declared size 18, regular white text, black stroke, transparent background, four-percent offset, and ASS direct play. This verifies the server-side preset, not the iPhone's local preferences. Moonfin 2.5.1 includes a Mobile profile and a Load Profile action in its [plugin settings screen](https://github.com/Moonfin-Client/Moonfin-Core/blob/f18c45b/lib/ui/screens/settings/plugin_settings_screen.dart). If the phone's values differ, open Settings > Integrations > Moonbase Plugin, select Mobile, and tap Load Profile, then inspect Subtitle Customization. Avoid Sync to Profile when trying to receive the server preset, since that uploads the phone's current values.

The [2.5.1 Apple subtitle overlay](https://github.com/Moonfin-Client/Moonfin-Core/blob/f18c45b/tvos/Runner/Playback/Aether/SubtitleOverlay.swift) and the [2.6.0 overlay](https://github.com/Moonfin-Client/Moonfin-Core/blob/b86bbe6021eff5befdf311134bf3e831c032f21f/tvos/Runner/Playback/Aether/SubtitleOverlay.swift) draw ordinary text with attributed-string backgrounds and expose no caption-corner-radius preference. Neither the server preset nor Jellyfin Web CSS can make those native captions rounded. The 2.6.0 ASS font fix applies to embedded tracks; the external ASS path needs a separate fix.

## External ASS on Moonfin iOS 2.6.0

Checked 2026-10-06 against Moonfin Core 2.6.0 and its pinned AetherEngine 6.89.1. A live iOS 2.6.0 playback session selected an English external ASS track, while Jellyfin Web rendered that track's styling correctly. AetherEngine's [format contract](https://github.com/superuser404notfound/AetherEngine/blob/72b0cec29007dfdffbedbb34d0527369d21c77e8/docs/formats.md) puts an embedded ASS header on `TrackInfo.assHeader` but an external sidecar's header on `engine.sidecarASSHeader`. Its [external-track constructor](https://github.com/superuser404notfound/AetherEngine/blob/72b0cec29007dfdffbedbb34d0527369d21c77e8/Sources/AetherEngine/Subtitles/ExternalSubtitleTrack.swift) creates `TrackInfo` without an ASS header. Moonfin's [Apple wrapper](https://github.com/Moonfin-Client/Moonfin-Core/blob/b86bbe6021eff5befdf311134bf3e831c032f21f/tvos/Runner/Playback/Aether/AetherPlayerWrapper.swift) enters libass only when the active track's `assHeader` is non-null; otherwise it strips ASS markup and renders plain text. Thus the upgrade fixes embedded ASS fonts but leaves external ASS sidecars unstyled on the native Apple backend. This is a source-level diagnosis; native iPhone rendering still needs a before-and-after visual check.

The available workaround is to turn off ASS/SSA Direct Play on the affected client. Moonfin's [device profile builder](https://github.com/Moonfin-Client/Moonfin-Core/blob/b86bbe6021eff5befdf311134bf3e831c032f21f/lib/playback/device_profile_builder.dart) then advertises ASS as `Encode`, so Jellyfin can burn the authored style into transcoded video. This uses substantial server resources and makes captions part of the picture. Keep the workaround scoped to the affected client or mobile profile after checking playback quality; embedded ASS and other players need no such change. The native fix is for Moonfin to read `engine.sidecarASSHeader` when its active ASS track is external.

## Jellyfin Web upstream review

Checked 2026-10-06 against Jellyfin Web 12.1 and
[master at 1e507c5](https://github.com/jellyfin/jellyfin-web/blob/1e507c588f353482a00333f84e36ddb7c8fc8221/src/scripts/settings/userSettings.js).
The subtitle getter passes the shared defaults object as the destination of
`Object.assign`. A saved choice then becomes the default for another local
account or settings key. A returned object can also modify those defaults.
The regression test fails on unpatched 12.1 and passes when the getter merges
into a fresh object. This one-line repair is a focused upstream candidate.
The local temporary fix carries the same patch and retains its revision guard
until the pinned package contains a release with the repair.
The open [per-title PR #7827](https://github.com/jellyfin/jellyfin-web/pull/7827)
copies defaults for its new fallback getter but leaves the existing getter's
mutation in place. The focused repair does not duplicate that PR.

The background selector is useful locally, but the current patch exposes four
presets and retains arbitrary saved colors without offering a way to choose a
new arbitrary color. An upstream feature should settle that interaction,
localization, and browser support before a PR. The local selector now uses
Jellyfin's existing translated labels. [Issue #1425](https://github.com/jellyfin/jellyfin-web/issues/1425)
concerns an unwanted browser or operating-system background, and
[issue #5592](https://github.com/jellyfin/jellyfin-web/issues/5592)
concerns styles that do not apply in some clients. Neither demonstrates that
the hidden background field should become this particular selector.

The viewport font baseline, rounded HTML background, and ASS prescale factor
are personal presentation choices. They have different effects across native
cues, HTML text, ASS, and older browser engines. The open
[size-slider PR #8385](https://github.com/jellyfin/jellyfin-web/pull/8385)
already addresses size control. [Issue #2248](https://github.com/jellyfin/jellyfin-web/issues/2248)
diagnosed pixelated subtitles as source PGS bitmaps, so it does not support
the ASS prescale change. Keep these rendering choices in the personal package
unless playback evidence establishes a specific upstream defect.
