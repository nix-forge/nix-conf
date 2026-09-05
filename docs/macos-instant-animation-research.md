# macOS instant animation research

Research date: 2026-09-02

Tested host: macOS 26.6.2, build 25G83

## Conclusion

The current `instant` profile has one direct logic error. It sets
`system.defaults.universalaccess.reduceMotion` to `false`. Apple identifies
Reduce Motion as the supported control for movement while switching desktops,
so the profile disables the setting most relevant to the reported Spaces
animation.

Fixing that value should replace the large horizontal Spaces movement with the
reduced-motion presentation. It cannot promise a zero-duration native Spaces
switch. Apple documents no setting or public API that fully disables that
transition. Apple describes Reduce Motion as reducing motion, and its SwiftUI
guidance explicitly permits replacing a slide with a cross-fade.

[Apple: Customize onscreen motion on Mac](https://support.apple.com/guide/mac-help/customize-onscreen-motion-mchlc03f57a1/mac)
[Apple: `accessibilityDisplayShouldReduceMotion`](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion)
[Apple: `accessibilityPrefersCrossFadeTransitions`](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilitypreferscrossfadetransitions)

For truly instant workspace switching, this repository already has the better
mechanism: AeroSpace workspaces. AeroSpace deliberately avoids native macOS
Spaces because Apple does not expose a public Spaces API and the native switch
animation cannot be disabled. Its workspaces switch without the native Spaces
transition. AeroSpace also publishes commands intended for trackpad gesture
handlers.

[AeroSpace guide source: Emulation of virtual workspaces](https://github.com/nikitabobko/AeroSpace/blob/c548c7f879164c7ab1acde7ecd88f4f19eb53d21/docs/guide.adoc#L428-L446)
[AeroSpace goodies source: Use trackpad gestures to switch workspaces](https://github.com/nikitabobko/AeroSpace/blob/c548c7f879164c7ab1acde7ecd88f4f19eb53d21/docs/goodies.adoc#L70-L89)

## What is wrong in the current module

The current expression is:

```nix
universalaccess = {
  reduceTransparency = lib.mkDefault cfg.reduceTransparency;
}
// lib.optionalAttrs (cfg.motion != "normal") {
  reduceMotion = lib.mkDefault (cfg.motion == "reduced");
};
```

It evaluates as follows:

| Profile | `reduceMotion` |
| --- | --- |
| `normal` | unmanaged |
| `reduced` | `true` |
| `instant` | `false` |

On the tested host, the active preference confirms the bad result:

```text
$ defaults read com.apple.universalaccess reduceMotion
0
$ xcrun swift -e 'import AppKit; print(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)'
false
```

The `instant` profile should set `reduceMotion = true`. nix-darwin's own option
description says this setting disables animation when switching screens or
opening apps. Its activation code writes the setting to the primary user's
`com.apple.universalaccess` domain.

[nix-darwin `universalaccess.reduceMotion` source](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults/universalaccess.nix#L18-L24)
[nix-darwin defaults writer](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults-write.nix#L12-L16)

Two other choices conflict with the name `instant`:

- `expose-animation-duration` is set to `0.1`, not `0.0`.
- The cleanup list always deletes Finder's `DisableAllAnimations` and Dock's
  `springboard-show-duration` and `springboard-hide-duration`. An instant
  profile cannot manage those keys until cleanup stops deleting them.

## Recommended settings

### Supported accessibility setting

Set this for both `reduced` and `instant`:

```nix
system.defaults.universalaccess.reduceMotion = true;
```

This is the only Apple-supported control in this list. Apple explicitly says it
affects opening apps, switching desktops, and Notification Center. The current
Desktop & Dock settings contain no Spaces animation toggle or duration control.

[Apple: Change Desktop & Dock settings](https://support.apple.com/guide/mac-help/change-desktop-dock-settings-mchlp1119/26/mac/26)

`reduceTransparency` is independent. It can reduce compositing and visual
clutter, but it does not control Spaces transition timing. Keeping it optional
is correct.

### Typed nix-darwin timing controls

These are the best declarative settings for an `instant` profile because the
repository's pinned nix-darwin revision has typed options for them:

```nix
system.defaults.NSGlobalDomain = {
  NSAutomaticWindowAnimationsEnabled = false;
  NSScrollAnimationEnabled = false;
  NSUseAnimatedFocusRing = false;
  NSWindowResizeTime = 0.001;
};

system.defaults.dock = {
  autohide-delay = 0.0;
  autohide-time-modifier = 0.0;
  expose-animation-duration = 0.0;
  launchanim = false;
  mineffect = "scale";
};
```

Coverage:

| Setting | UI it affects | Current profile |
| --- | --- | --- |
| `NSAutomaticWindowAnimationsEnabled` | Cocoa windows and popovers | correct |
| `NSScrollAnimationEnabled` | smooth scrolling in AppKit controls | correct |
| `NSUseAnimatedFocusRing` | keyboard focus ring | missing |
| `NSWindowResizeTime` | AppKit window resize transitions | correct |
| `autohide-delay` | wait before the Dock appears | correct |
| `autohide-time-modifier` | Dock show and hide animation | correct |
| `expose-animation-duration` | Mission Control presentation | currently `0.1` |
| `launchanim` | bouncing launch animation in the Dock | correct |
| `mineffect = "scale"` | window minimize style | shortest supported style, still animated |

[nix-darwin NSGlobalDomain animation options](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults/NSGlobalDomain.nix#L176-L183)
[nix-darwin focus, scroll, and resize options](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults/NSGlobalDomain.nix#L240-L263)
[nix-darwin Dock timing options](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults/dock.nix#L31-L88)
[macos-defaults tested Dock autohide duration](https://github.com/yannbertrand/macos-defaults/blob/ae534d931241dd8c62a813818bcb921c8c9313d8/docs/dock/autohide-time-modifier.md#L13-L68)
[macos-defaults tested Dock autohide delay](https://github.com/yannbertrand/macos-defaults/blob/ae534d931241dd8c62a813818bcb921c8c9313d8/docs/dock/autohide-delay.md#L13-L54)

"Typed" means nix-darwin validates the Nix value and writes the expected
preference domain. It does not mean Apple supports the preference. In
particular, `expose-animation-duration` is still a nix-darwin option, but its
literal name is absent from the Dock executable on macOS 26.6.2. Keep it as a
best-effort Mission Control tweak. Do not expect it to alter an interactive
Spaces swipe.

The option entered nix-darwin in 2017. Its upstream tests check generated
`defaults write` commands, not visible macOS behavior. A current Mission Control
replacement project reports that the key does not fix modern macOS animation.

[nix-darwin PR 58](https://github.com/nix-darwin/nix-darwin/pull/58)
[nix-darwin defaults serialization tests](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/tests/system-defaults-write.nix#L32-L74)
[FastMissionControl current behavior note](https://github.com/tomeraviv/FastMissionControl/blob/35e8d659b63a2e9ea831f933be2db3b9e10b1bc2/README.md#L1-L12)

nix-darwin restarts the user's Dock whenever it writes Dock settings. That is
necessary because Dock owns Mission Control and native Spaces presentation.

[nix-darwin Dock restart activation](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults-write.nix#L154-L158)

### Private settings with current binary evidence

Apple does not document these keys. They should live behind an explicitly named
compatibility option and should have version-sensitive tests. They are reasonable
for `instant`, but they are not stable API.

```nix
system.defaults.CustomUserPreferences = {
  "com.apple.finder".DisableAllAnimations = true;
  "com.apple.dock" = {
    springboard-show-duration = 0.0;
    springboard-hide-duration = 0.0;
    springboard-page-duration = 0.0;
  };
};
```

Inspection of Apple's installed Dock and Finder executables on macOS 26.6.2
found the literal preference names `springboard-show-duration`,
`springboard-hide-duration`, `springboard-page-duration`, `launchanim`,
`autohide-time-modifier`, `DisableAllAnimations`, and `AnimateInfoPanes`. This
shows the current binaries know the names, but it does not guarantee that every
code path still honors them.

Finder must be restarted after changing `DisableAllAnimations`. Dock is already
restarted by nix-darwin when typed Dock settings are present. Applications that
read global AppKit settings only at startup must also be reopened.

### Private settings with weaker evidence

Common dotfiles snippets set the following values:

```nix
system.defaults.CustomUserPreferences.NSGlobalDomain = {
  QLPanelAnimationDuration = 0.0;
  NSDocumentRevisionsWindowTransformAnimation = false;
  NSToolbarFullScreenAnimationDuration = 0.0;
  NSBrowserColumnAnimationSpeedMultiplier = 0.0;
};
```

The claimed targets are Quick Look, document version views, full-screen toolbar
changes, and AppKit column browsers. nix-darwin has no typed options for them,
and the upstream sources surveyed do not establish their behavior on Tahoe.
They were not found as plain strings in the standalone system binaries checked
on macOS 26.6.2. AppKit now lives largely in the dyld shared cache, so that test
is inconclusive. Do not enable these by default. If they are offered at all,
label them experimental and verify them visually after every major macOS update.

Do not add `NSScrollViewRubberbanding = false` to the base instant profile.
Rubber-band overscroll is an interaction behavior rather than transition delay,
and disabling it changes scrolling feedback. It belongs in a separate UX option.

## Native Spaces cannot be made fully instant by defaults

Do not add this old key:

```text
defaults write com.apple.dock workspaces-swoosh-animation-off -bool true
```

It is absent from both nix-darwin and the Dock executable shipped with macOS
26.6.2. It dates to old Spaces implementations and there is no current Apple or
upstream source showing that Tahoe honors it. Writing an unknown preference is
harmless but misleading because `defaults` succeeds even when no process reads
the key.

The same warning applies to copying `com.apple.Accessibility.ReduceMotionEnabled`
from shell snippets. On the tested host that key is `1` while Apple's public
AppKit API reports Reduce Motion as `false`. The documented nix-darwin mapping to
`com.apple.universalaccess.reduceMotion` agrees with AppKit and should remain the
source of truth.

Tools that make native Space transitions genuinely instant use private APIs or
patch Dock. yabai's own documentation says its robust implementation uses a
scripting addition, and several Space-management features require partially
disabling System Integrity Protection. Weakening SIP only to remove animation is
not a sound security trade.

[yabai documentation: `skip_window_focus_animation`](https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/doc/yabai.asciidoc#L178-L182)
[yabai maintainer: native duration is patched in Dock](https://github.com/asmvik/yabai/issues/1235#issuecomment-1105251897)
[yabai maintainer: why Space control requires Dock injection](https://github.com/asmvik/yabai/issues/1863)

## Best fit for this repository

The repository already enables AeroSpace and defines named workspaces plus
instant keyboard bindings. The clean implementation is:

1. Fix `instant` so it enables Apple's Reduce Motion setting.
2. Complete the typed nix-darwin timing controls and add the small group of
   current-binary-backed private settings.
3. Keep native Spaces available for full-screen apps, but do not promise a
   zero-duration native swipe.
4. For instant trackpad navigation, map the gesture to AeroSpace's published
   next and previous workspace commands and disable macOS's overlapping
   "Swipe between full-screen applications" gesture.

AeroSpace's documentation recommends these commands for gesture handlers:

```text
aerospace eval 'list-workspaces --monitor mouse --visible | workspace --stdin next; workspace next --wrap-around'
aerospace eval 'list-workspaces --monitor mouse --visible | workspace --stdin next; workspace prev --wrap-around'
```

A gesture helper must read trackpad input. Prefer a small, source-built helper,
pin its source, and document its Input Monitoring or Accessibility permission.
Do not install a remote script with `curl | bash`. AeroSpace itself cautions
users to trust the author or inspect and build the helper from source.

## Verification after implementation

An activation check should evaluate all declared values, then runtime checks
should confirm the active user domain:

```text
defaults read com.apple.universalaccess reduceMotion
defaults read -g NSAutomaticWindowAnimationsEnabled
defaults read -g NSScrollAnimationEnabled
defaults read -g NSUseAnimatedFocusRing
defaults read -g NSWindowResizeTime
defaults read com.apple.dock autohide-delay
defaults read com.apple.dock autohide-time-modifier
defaults read com.apple.dock expose-animation-duration
defaults read com.apple.dock launchanim
defaults read com.apple.finder DisableAllAnimations
```

The strongest Reduce Motion check is Apple's API:

```text
xcrun swift -e 'import AppKit; print(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)'
```

It should print `true`. A visual test should cover native desktop swipe,
Mission Control, Dock autohide, opening and closing a Finder window, Quick Look,
and an AeroSpace workspace switch. The native desktop test should expect reduced
motion, usually a cross-fade, rather than an instantaneous cut.
