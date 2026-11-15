# File manager directories and bookmarks

Reviewed: 2026-10-07. Scope: this repository's XDG directories, Nautilus,
GTK file choosers, KDE places, and Finder favorites. Upstream sources retrieved
on that date; Home Manager revision `4b9add8645d5e2b0f7de18f7a442d08fe2bdcc91`.

## Answer

Directory creation and sidebar bookmarks need separate configuration. Keep
Home Manager's XDG directory definitions as the path authority, then add missing
bookmarks to each supported format without replacing personal bookmarks. Use
the repository's existing Finder integration on Darwin.

The appropriate common set is the enabled standard directories, Projects,
Developer, and Screenshots. Projects, Developer, and Screenshots are repository
choices rather than the eight historical freedesktop defaults. Include Templates
and Public when enabled. A null directory should remain disabled. Do not add
private network locations or hidden configuration directories by default.

## Findings and sources

### XDG paths and creation

The freedesktop defaults name Desktop, Downloads, Templates, Public, Documents,
Music, Pictures, and Videos. These are user content locations, distinct from
the XDG configuration, data, state, and cache roots. See the upstream
[user-dirs defaults](https://cgit.freedesktop.org/xdg/xdg-user-dirs/tree/user-dirs.defaults).

The pinned Home Manager module also supports `projects`. Its
`xdg.userDirs.createDirectories` activation creates every enabled directory,
including `extraConfig` values, after `linkGeneration`. Null standard options
are omitted. `setSessionVariables` exports the configured bindings, but exporting
them does not create bookmarks. See the pinned
[user-dirs module](https://github.com/nix-community/home-manager/blob/4b9add8645d5e2b0f7de18f7a442d08fe2bdcc91/modules/misc/xdg/user-dirs.nix).

Locally, [the XDG module](../../modules/home/xdg/default.nix) already enables creation
and defines Projects, Developer, and Screenshots. Adding a second directory
creation service would duplicate its responsibility.

### GTK and Nautilus

Nautilus reads and monitors `$XDG_CONFIG_HOME/gtk-3.0/bookmarks`. Each line is
a URI followed by an optional space and label. URI paths need percent encoding
for spaces, Unicode, and reserved characters. Bookmarks are writable application
state; Nautilus also writes this file when users change the sidebar. See
[Nautilus's bookmark implementation](https://github.com/GNOME/nautilus/blob/a720b052fd1433aca3c99bb01d880285d304e2e9/src/nautilus-bookmark-list.c).

GTK 4 deliberately uses the GTK 3 bookmark file because the format has not
changed. It falls back to `$HOME/.gtk-bookmarks` when the modern file does not
exist. There is no need to invent a `gtk-4.0/bookmarks` file. See
[GTK's bookmark manager](https://github.com/GNOME/gtk/blob/9b7a28d301eeee77c479c8529604b4f23f8b91a1/gtk/gtkbookmarksmanager.c).

GNOME documents adding, removing, and renaming sidebar bookmarks. A bookmark
label does not rename the underlying folder. See
[GNOME's bookmark help](https://help.gnome.org/gnome-help/nautilus-bookmarks-edit.html).
The separate `xdg-user-dirs-gtk` login helper seeds a bookmark file only when
none exists. It cannot repair an existing incomplete file. See its
[README](https://github.com/GNOME/xdg-user-dirs-gtk/blob/master/README).

Home Manager's `gtk.gtk3.bookmarks` writes the entire bookmark file as managed
configuration when the list is nonempty. This is suitable for an exclusively
declarative list, but an additive writable reconciler better satisfies the
requirement to retain GUI-added bookmarks. See the pinned
[GTK 3 module](https://github.com/nix-community/home-manager/blob/4b9add8645d5e2b0f7de18f7a442d08fe2bdcc91/modules/misc/gtk/gtk3.nix).

Thunar's shortcuts model loads, monitors, and saves GTK bookmarks through its
bookmark helper. This provides a shared backend rather than a separate Thunar
favorites format. See
[Thunar's shortcuts model](https://github.com/xfce-mirror/thunar/blob/b1d2264ccae761e6bd1384fb992c4ea3d4564c44/thunar/thunar-shortcuts-model.c).

### KDE and other front ends

KDE's `KFilePlacesModel` uses `$XDG_DATA_HOME/user-places.xbel`. On initial
creation it adds standard folders only when they exist. KDE places need their
own XML adapter; copying GTK text into this file would corrupt it. Preserve
existing bookmark metadata, hidden state, remote URLs, and separators. See
[KIO's places model](https://github.com/KDE/kio/blob/69f11e2c2638202a7f09a1eac07fe11800850657/src/filewidgets/kfileplacesmodel.cpp).
For a newly seeded file, leave KIO's root version metadata absent. The model
treats an absent version as zero and then adds its Home, Network, Trash, and
other available defaults, deduplicating existing URLs. Setting the current
version prematurely would bypass that initialization.

Finder already has an additive managed-favorites module in
[finder-favorites.nix](../../modules/home/macos/finder-favorites.nix). Its default
list omitted Projects and Templates before this change. It now includes both
when enabled, matching Linux's standard directory coverage. Its backend limitations remain documented
in [the Finder research](finder-favorites-modern-replacement-research.md).

Repository search found Nautilus and Finder configuration, and no configured
terminal file manager. Terminal managers need their own navigation bindings or
plugins. For example, Yazi documents navigation in its
[keymap configuration](https://yazi-rs.github.io/docs/configuration/keymap/).
Supporting GTK and KDE formats does not establish support for every independent
file manager or custom in-application browser.

## Validation and limits

This investigation inspected repository modules, the pinned Home Manager source,
and upstream application source. Implementation validation passed eight CLI
behavior tests, built the Linux reconciliation command, and evaluated Linux and
Darwin Home Manager assertions and generated configuration. Tests cover custom
entries, repeated execution, URI escaping, legacy GTK migration, KDE metadata
and namespace prefixes, malformed XML, entity rejection, symlinks, and dry runs.
The bookmarks were applied on Linux. No full desktop rebuild, GUI interaction
test, or native Darwin activation ran. The cited GNOME, KDE, and Thunar revisions are upstream
observations, not a claim that every installed package uses those revisions.

## Implication for this repository

Use a common enabled-directory catalog. Reconcile local bookmarks by their
normalized local file URI, add missing configured entries, and preserve personal
entries and labels. Run reconciliation after XDG directory creation, write files
atomically, and make repeated activation a no-op when nothing changes. Keep
GTK legacy compatibility explicit and retain KDE XML metadata. Treat the
result as configuration until activation and native GUI checks verify it.
