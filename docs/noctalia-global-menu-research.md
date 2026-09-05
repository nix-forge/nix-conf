# Noctalia global application menu research

Research date: 2026-09-03. This review covers the repository's pinned Noctalia 5.0.0 and Hyprland 0.56.2 setup.

## Decision

Do not add a full macOS-style global application menu to the baseline now. It is possible on Wayland, but not through a portable Wayland standard and not as a Noctalia setting. The reliable native path currently depends on compositor support that Hyprland 0.56.2 does not provide. A menu copied through AT-SPI could be built as an experimental Noctalia v5 plugin, but it would usually duplicate rather than replace the application's own menu and therefore would not save vertical space.

Use per-application menu hiding where it is useful. In particular, VS Code officially supports `window.menuBarVisibility = "toggle"` or `"hidden"`; `toggle` restores it with one press of Alt. This repository already uses VS Code's custom title bar and has that setting prepared but commented out. [VS Code menu-bar documentation](https://code.visualstudio.com/docs/editing/getting-started/userinterface#_hide-the-menu-bar-windows-linux)

An aesthetic v5 prototype is reasonable if the goal is the appearance in the reference image. It should show the active application's name and, when available, copied menu actions. It should not suppress in-window menus or claim universal compatibility.

## Current repository fit

- `flake.lock` pins Noctalia commit [`f96a407d`](https://github.com/noctalia-dev/noctalia/commit/f96a407deb109c9db6f29db75e6fe487a5289e02), which evaluates to Noctalia 5.0.0. This is the native C++ v5 shell with Luau plugins. The documentation labels the Quickshell shell as "v4 legacy." [Noctalia v5 documentation](https://docs.noctalia.dev/noctalia/)
- The pinned [widget factory](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/bar/widget_factory.cpp) and [widget index](https://docs.noctalia.dev/noctalia/bar/widgets/) contain no application-menu widget. A new implementation would be a plugin plus, most likely, a sidecar service.
- `modules/home/desktop/config/noctalia.toml.in` reserves a fixed 34 logical-pixel top bar. Its start lane is `launcher`, `workspaces`, and `active_window`; the end lane is already dense. A prototype should replace or extend `active_window`, not append an unlimited menu strip.
- `homes/desktop/local/hyprland.nix` configures a 2562 by 1656 output at scale 1.5, yielding a 1708 by 1104 logical workspace. The existing bar consumes 34/1104, or 3.1 percent, of the logical height.
- The evaluated compositor is Hyprland 0.56.2. Its [protocol manager](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/managers/ProtocolManager.cpp) registers neither KDE's appmenu protocol nor GTK's shell protocol. Hyprland's maintainer previously described KDE's protocol as non-standard and declined to adopt it. [Hyprland discussion 1358](https://github.com/hyprwm/Hyprland/discussions/1358)

Noctalia v5's beta plugin API can render a row of compact pointer buttons and open a panel. The bar itself never takes keyboard focus, and Noctalia's supplied context-menu request is a flat list of actions, headings, and separators. A faithful menu needs a custom panel for nested and dynamic submenus. The runtime can start and stream a sidecar process, but documents no direct general D-Bus client API. [Declarative UI constraints](https://docs.noctalia.dev/noctalia/plugins/development/declarative-ui/) [Runtime process API](https://docs.noctalia.dev/noctalia/plugins/development/runtime-api/#processes)

## Why Wayland is the blocker

A global menu needs two separate pieces:

1. A machine-readable menu tree. `com.canonical.dbusmenu` carries labels, nested items, enabled and visible state, icons, shortcuts, check/radio state, updates, `AboutToShow`, and activation events. [Canonical DBusMenu interface XML](https://github.com/gnustep/libs-dbuskit/blob/master/Bundles/DBusMenu/com.canonical.dbusmenu.xml)
2. A trustworthy association between that D-Bus object and the focused window.

On X11, `com.canonical.AppMenu.Registrar` associates a menu service and object path with an X Window ID. Its own interface explicitly describes the key as an XWindow ID, so that mapping cannot identify a native `wl_surface`. [KDE registrar interface](https://github.com/KDE/plasma-workspace/blob/master/appmenu/com.canonical.AppMenu.Registrar.xml)

KDE solves the Wayland association with its private [`org_kde_kwin_appmenu_manager`](https://github.com/KDE/plasma-wayland-protocols/blob/master/src/protocols/appmenu.xml): the client attaches a D-Bus service and object path to its `wl_surface`. KWin then exposes those values with the active toplevel for Plasma's appmenu consumer. [KDE window-management protocol](https://github.com/KDE/plasma-wayland-protocols/blob/master/src/protocols/plasma-window-management.xml) [Plasma appmenu model](https://github.com/KDE/plasma-workspace/blob/master/applets/appmenu/appmenumodel.cpp)

The proposed cross-desktop `xdg-dbus-annotation-v1` would generalize this association and explicitly names Unity-style application menus as a use case. Its merge request has remained open since October 2020 and is still unmerged, so it is not a protocol applications can depend on today. [wayland-protocols merge request 52](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/merge_requests/52)

Wayland itself therefore does not rule out a global menu. It works in a coordinated stack such as Qt, KWin, and Plasma. It does not work portably across an arbitrary compositor and bar, and the required native association is missing in this Hyprland setup.

There is also a dangerous partial configuration. Qt creates a D-Bus platform menubar when `com.canonical.AppMenu.Registrar` exists. On X11 it registers the XID; on Wayland it can attach the menu only if the compositor advertises KDE's appmenu manager, otherwise the Wayland registration function returns. Qt documents that a native menu is removed from its parent window. Starting a registrar without the Wayland protocol can therefore hide a Qt application's local menu while leaving the bar unable to find it. [Qt `QMenuBar` behavior](https://doc.qt.io/qt-6/qmenubar.html#qmenubar-as-a-global-menu-bar) [Qt registrar detection](https://github.com/qt/qtbase/blob/362f1b4eaf5d4c5a70368a9ccaac11f2b99fad75/src/gui/platform/unix/qgenericunixtheme.cpp) [Qt Wayland registration](https://github.com/qt/qtbase/blob/362f1b4eaf5d4c5a70368a9ccaac11f2b99fad75/src/plugins/platforms/wayland/qwaylandplatformservices.cpp)

## Application compatibility

| Application or stack | Native mechanism | Result on this setup |
| --- | --- | --- |
| Qt Widgets applications | `QMenuBar` exports `com.canonical.dbusmenu`; native Wayland association uses KDE's protocol. | Best potential compatibility, but blocked for native Wayland by Hyprland. XWayland can use the XID registrar path. Qt Quick Controls' ordinary `MenuBar` is not the same promise; Qt only documents it as native on macOS. [Qt Widgets](https://doc.qt.io/qt-6/qmenubar.html) [Qt Quick Controls](https://doc.qt.io/qt-6/qml-qtquick-controls-menubar.html#native-menu-bars) |
| GTK `GtkApplication` | Exports `GMenuModel` actions and menu models. GTK's private `gtk_shell1` associates its D-Bus paths with a Wayland surface and advertises whether the shell displays the menu. | Hyprland does not provide `gtk_shell1`, so GTK keeps a local fallback where applicable. Legacy `appmenu-gtk-module` targets GTK 2/3 and still tracks native-Wayland support as open work. [GTK application window](https://docs.gtk.org/gtk4/class.ApplicationWindow.html) [GTK Wayland protocol](https://gitlab.gnome.org/GNOME/gtk/-/blob/a27f4faac0b6da45bc62d6301156ad4858c3fd2a/gdk/wayland/protocol/gtk-shell.xml) [GTK-module Wayland issue](https://gitlab.com/vala-panel-project/vala-panel-appmenu/-/work_items/380) |
| Modern GTK4/libadwaita apps, including Nautilus | Usually put a primary popover menu and actions inside a header bar. GTK4 removed the old `GtkMenuBar`; `GtkPopoverMenuBar` is its model-based replacement. | Often no independent full-width menu row exists to remove. Moving the menu does not remove the header bar or its navigation and window controls, so the height saving is normally zero. [GTK4 migration guide](https://docs.gtk.org/gtk4/migrating-3to4.html#gtkmenu-gtkmenubar-and-gtkmenuitem-are-gone) [GNOME header-bar guidance](https://developer.gnome.org/hig/patterns/containers/header-bars.html) |
| Zen/Firefox | Current Mozilla code enables a native menubar only when its global-menu preferences are enabled and, on Wayland, KDE's appmenu manager is present. | Blocked by Hyprland's missing protocol. An AT-SPI walker is also weak because browser menus can be lazy. [Mozilla `NativeMenubar` check](https://searchfox.org/mozilla-central/source/widget/gtk/nsLookAndFeel.cpp) |
| Chromium and Electron apps | Chromium gained the KDE Wayland appmenu association in 2025. Electron's public Linux API still specifies an application menu at the top of each window, and custom HTML menus are not native menu models. | Protocol support in a recent Chromium base is insufficient without Hyprland support and application use of a native menu. VS Code's built-in hide/toggle setting is more dependable. [Chromium Wayland appmenu commit](https://chromium.googlesource.com/chromium/src/+/9c30fb37950c6a0a7ab2875f38ca3953e27963ae) [Electron `Menu`](https://www.electronjs.org/docs/latest/api/menu/) |
| LibreOffice | Uses its own VCL toolkit and has a traditional, separate menu row. [LibreOffice VCL overview](https://github.com/LibreOffice/core/blob/master/vcl/README.md) | It is the main installed application likely to recover meaningful height, but its exact backend/export behavior must be tested. Do not infer Qt or GTK global-menu support merely from the selected VCL integration backend. |
| Ghostty, Chrome, Discord, Signal, Spotify, and similar custom UIs | No traditional native `File/Edit/View` model in the common UI. | Usually nothing useful to export and no standalone menu row to reclaim. A generic app-name or window-actions menu is possible, but it is not the application's menu. |

## The existing Noctalia appmenu project does not fit

[`yolo-labz/noctalia-appmenu`](https://github.com/yolo-labz/noctalia-appmenu/blob/29d099559773cd78f79133bcbca8c5ec96b2eef3/README.md) is useful evidence that an AT-SPI approximation can be built. It is not installable as the answer here:

- It targets legacy Noctalia v4, with a QML bar widget hosted by Quickshell. This repository runs native Noctalia v5 with Luau plugins.
- It is niri-only. Its bridge follows niri's IPC; Hyprland support is explicitly deferred.
- Its current AT-SPI mode copies menu accessibility nodes and invokes their actions. Its Home Manager option `hideInWindowMenubar` is explicitly a no-op, so the project's current architecture does not reclaim the local menu row. [Module option source](https://github.com/yolo-labz/noctalia-appmenu/blob/29d099559773cd78f79133bcbca8c5ec96b2eef3/nix/module.nix#L94-L112)
- Its own compatibility notes fall back for Firefox, Electron without accessibility flags, and closed GTK4 popover menus. Enabling Chromium accessibility globally merely to scrape a menu is also unattractive because Electron warns that rendering the accessibility tree can significantly affect performance. [Electron accessibility warning](https://www.electronjs.org/docs/latest/api/app/#appaccessibilitysupportenabled-macos-windows)

Quickshell does not rescue the current v5 shell. Its released `DBusMenuHandle` is uncreatable from QML. [Quickshell 0.3 API](https://quickshell.org/docs/v0.3.0/types/Quickshell.DBusMenu/DBusMenuHandle/) Pull request 484 would expose it for global-menu use, but remains open and applies to Quickshell, not Noctalia v5. [Quickshell pull request 484](https://github.com/quickshell-mirror/quickshell/pull/484)

## Space and UX assessment

Adding menu labels inside the existing 34 px bar costs no additional vertical height if they fit. It also saves nothing by itself. Space is recovered only when a supported application removes a separate local menu row and the global consumer remains available.

This does not make a tiled window's outer rectangle smaller. It gives that window a little more room for its document, editor, or web content inside the same tile. If the application keeps its local menu, the gain is zero.

For scale, removing a 24 to 32 logical-pixel menu row would recover about 2.2 to 2.9 percent of this 1104-pixel logical workspace per affected window. That is a useful one-row gain in LibreOffice or a classic Qt editor, but the estimate is app and theme dependent. The fixed 34 px Noctalia bar remains. VS Code may gain less because its custom title bar already combines controls; Nautilus and most modern GNOME apps gain none because their menus live in a header bar that still has other jobs.

The design also has costs in a tiled desktop:

- The menu changes with focus while several windows remain visible. The application name is necessary to make the target clear.
- The pointer travels from a window to the top edge, which is more noticeable on large or multi-monitor layouts.
- Long localized menu strips can collide with the centered clock and the already dense status lane at 1708 logical pixels. Overflow needs an explicit design.
- Alt-letter mnemonics, keyboard traversal, dynamic `AboutToShow` menus, nested submenus, check/radio state, and focus-safe popup dismissal all need real menu semantics. A row of command buttons is not enough.
- A blank or stale global menu is worse than a duplicate. Local menus must remain visible whenever export, surface association, or the consumer fails.

## Recommended path

1. Keep the current fixed bar and `active_window` identity.
2. Enable per-app hiding only where the application has a reliable recovery path. The first low-risk candidate is VS Code with `window.menuBarVisibility = "toggle"`. Test LibreOffice's own compact or tabbed UI options separately if its menu row is the practical concern.
3. If the visual style is still desirable, make a small Noctalia v5 prototype that replaces `active_window` with app icon/name and optional AT-SPI-derived actions. Keep every in-window menu visible. Treat missing menus as normal and fall back to app identity or compositor window actions.
4. Reconsider a space-saving global menu only when Hyprland implements a surface-to-D-Bus annotation protocol and Noctalia v5 has a maintained nested-menu consumer. Test native Wayland and XWayland separately across Qt Widgets, GTK3/4, Zen, VS Code/Electron, and LibreOffice, including focus changes and consumer failure.

The short answer is: yes on Wayland in a coordinated stack, no as a dependable global feature on this Hyprland and Noctalia stack today, and only a small real space win for the applications in this repository that still have a separate classic menubar.
