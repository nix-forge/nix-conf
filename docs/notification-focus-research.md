# Notification clicks and window activation

Reviewed: 2026-09-09. Scope: Noctalia 5.0.0 at `f96a407deb109c9db6f29db75e6fe487a5289e02` and Hyprland at `ee0409623e2d6a683374b39a32e0ac3d087841aa` on Wayland.

## Answer

Enabled `misc.focus_on_activate` in the desktop configuration and running session. A native Wayland application activation test failed with the previous setting and passed after enabling it. This removes the compositor's focus block for notifications whose applications supply an action and request window activation. The specific reported notification has not been reproduced, so its complete click path remains unverified.

There are separate limits in Noctalia. A toast only invokes an application action when the notification supplies `default`. Notification history exposes explicit action buttons; its card body does not have the toast's default-click handler. Notifications without an action, or history entries whose D-Bus lifetime has ended, need different handling.

## Findings and sources

### Installed components

Repository configuration selects `noctalia-personal` in [the desktop module](../modules/home/desktop/noctalia.nix). Its [source pin](../pkgs/pkgs/by-name/no/noctalia-personal/source.nix) is Noctalia 5.0.0 at `f96a407deb109c9db6f29db75e6fe487a5289e02`. This is the native C++ implementation; Quickshell documentation does not describe this installed package. Its local patches change icons and media presentation, not notification behavior.

The root flake's separate Noctalia input is `4ea0a7f0c7d00ac559a1029ccf8d0d1270b23c08`. The package source above is the relevant revision for runtime behavior. [The lockfile](../flake.lock) pins Hyprland at `ee0409623e2d6a683374b39a32e0ac3d087841aa`.

Initial runtime inspection found Noctalia's notification service active and reporting version 5.0.0, Hyprland running the pinned revision, and `hyprctl getoption misc:focus_on_activate` reporting false. After the fix and a configuration reload, that option reports true. Noctalia enables its notification daemon and action buttons.

### Noctalia already passes activation tokens

The pinned [toast handler](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/notification/notification_toast.cpp#L2285-L2302) handles a left click by invoking `default` only if that action exists. It requests a token for the toast's Wayland surface. This handler does not depend on `show_actions`.

The [Wayland connection](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/wayland/wayland_connection.cpp#L667-L694) requests an xdg activation token using the last input serial and source surface. The [D-Bus service](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/dbus/notification/notification_service.cpp#L504-L537) emits a nonempty `ActivationToken` before `ActionInvoked`. This matches the [freedesktop notification protocol](https://specifications.freedesktop.org/notification/latest/protocol.html#signals).

The current [Noctalia documentation](https://docs.noctalia.dev/noctalia/services/notifications/) describes `show_actions = false` as enabling default-click behavior. The installed revision's handler is broader. Changing that setting is not supported by the source evidence as the fix for this problem.

### Hyprland blocks the requested focus

The pinned [xdg activation handler](https://github.com/hyprwm/Hyprland/blob/ee0409623e2d6a683374b39a32e0ac3d087841aa/src/protocols/XDGActivation.cpp#L69-L88) resolves a valid token and target window, then calls `activate()` without forcing focus.

[Window activation](https://github.com/hyprwm/Hyprland/blob/ee0409623e2d6a683374b39a32e0ac3d087841aa/src/desktop/view/window/Window.cpp#L794-L818) marks the window urgent, then returns before focusing if the effective `focus_on_activate` setting is false. A window rule can override the global setting. Activation suppression rules can also block focus.

Hyprland documents both the [global option](https://wiki.hypr.land/configuring/core/config-options/) and the [per-window effect](https://wiki.hypr.land/configuring/core/rules/window-rules/). Enabling the option allows other activation requests as well as notification clicks. A rule for the affected application keeps the scope smaller, but does not distinguish notification clicks from that application's other requests.

### History and missing actions

The pinned [history card](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/control_center/tabs/notifications_tab.cpp#L395-L470) creates buttons for supplied actions. The `default` action's fallback label is Open. Its body has no handler that automatically invokes that action. [Invocation](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/control_center/tabs/notifications_tab.cpp#L1006-L1015) requires a pending D-Bus close.

The [manager](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/notification/notification_manager.cpp#L452-L499) rejects absent actions and history entries with no pending D-Bus lifetime. A generic window-focus fallback would therefore require an implementation change. Matching an application identifier alone would not reliably choose the originating window when several windows are open.

## Validation and limits

Read repository configuration and exact upstream sources; browsed official protocol and project documentation. Reviewed only the specific source paths above. Validation and targeted activation ran on the Linux desktop:

- A temporary GTK3 Wayland app created two windows, verified that the second window had focus, then called `present_with_time(0)` on the first. It reported `FAIL: activation left target unfocused` before the fix and `PASS: activation focused target` afterward. The test closed both windows and kept its script outside the repository.
- Built the generated Home Manager `hypr/hyprland.lua` file. Its diff against the installed file contained only the new `focus_on_activate = true` setting. The initial Git-filtered evaluation failed because unrelated storage work referenced untracked modules. The successful path-flake build included those modules.
- Installed the generated file through the live configuration symlink and retained it with a local Nix GC root. Recorded the previous symlink target beside that root. A normal Home Manager activation will install the setting from the Nix declaration.
- Reloaded Hyprland with `config-only`, confirmed the effective setting is true, and checked that `hyprctl configerrors` is empty. Nix formatting and whitespace checks passed.

No full system activation or physical notification-click test ran. The GTK test exercises application activation at the compositor boundary; it does not exercise Noctalia's click handler or the affected application's notification callback.

The affected application and whether the user clicked a toast or a history card remain unknown. We have not established whether its notification provides `default`, receives `ActionInvoked`, consumes `ActivationToken`, or requests compositor activation.

## Implication for this repository

The global setting now lives in [the desktop Hyprland module](../homes/desktop/local/hyprland.nix) as `wayland.windowManager.hyprland.settings.config.misc.focus_on_activate = true;`. An application-specific `hl.window_rule` with `focus_on_activate = true` could limit the change to matching windows if needed later. Neither setting is restricted to notification clicks.

If a notification still fails to focus its window, identify toast versus history behavior and inspect the application's supplied actions. Notifications without an action and clicks on history card bodies require separate application or Noctalia handling. Do not change `show_actions` solely on the basis of the documentation comment.
