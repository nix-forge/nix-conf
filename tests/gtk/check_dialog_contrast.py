"""Probe GTK 3 overwrite-dialog label contrast in the current desktop session.

Run with Python providing PyGObject and the GTK 3 typelib. GTK_THEME can select
an alternative base theme to reproduce a theme mismatch without changing dconf.
"""

from __future__ import annotations

import sys
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Sequence

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # ruff: ignore[module-import-not-at-top-of-file] - GTK must be versioned before importing it.

_SRGB_THRESHOLD = 0.04045
_MIN_CONTRAST = 4.5


def _luminance(rgb: Sequence[float]) -> float:
    linear = [
        c / 12.92 if c <= _SRGB_THRESHOLD else ((c + 0.055) / 1.055) ** 2.4 for c in rgb
    ]
    return sum(
        c * weight for c, weight in zip(linear, (0.2126, 0.7152, 0.0722), strict=True)
    )


def _measure(dialog: Gtk.MessageDialog, buttons: list[Gtk.Widget]) -> list[str]:
    found, background = dialog.get_style_context().lookup_color("dialog_bg_color")
    if not found:
        return ["The theme does not define dialog_bg_color"]
    bg = (background.red, background.green, background.blue)
    failures = []
    for button in buttons:
        if not isinstance(button, Gtk.Button):
            failures.append("Dialog response is not a button")
            continue
        label = button.get_child()
        if label is None:
            failures.append("Dialog button has no label")
            continue
        for name, state in (
            ("normal", Gtk.StateFlags.NORMAL),
            ("hover", Gtk.StateFlags.PRELIGHT),
            ("focused", Gtk.StateFlags.FOCUSED),
            ("backdrop", Gtk.StateFlags.BACKDROP),
        ):
            button.set_state_flags(state, True)
            label.set_state_flags(state, True)
            color = label.get_style_context().get_color(label.get_state_flags())
            fg = (color.red, color.green, color.blue)
            visible = [
                c * color.alpha + b * (1 - color.alpha)
                for c, b in zip(fg, bg, strict=True)
            ]
            a, b = sorted((_luminance(visible), _luminance(bg)))
            ratio = (b + 0.05) / (a + 0.05)
            sys.stdout.write(f"{button.get_label()} {name}: {ratio:.2f}:1\n")
            if ratio < _MIN_CONTRAST:
                failures.append(f"{button.get_label()} {name}")
    return failures


def _main() -> int:
    Gtk.init()
    dialog = Gtk.MessageDialog(
        message_type=Gtk.MessageType.QUESTION,
        text='A file named "example.csv" already exists. Do you want to replace it?',
    )
    dialog.format_secondary_text("Replacing it will overwrite its contents.")
    buttons = [
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL),
        dialog.add_button("Replace", Gtk.ResponseType.ACCEPT),
    ]
    dialog.set_default_response(Gtk.ResponseType.ACCEPT)
    dialog.show_all()
    failures = ["Probe did not complete"]

    def inspect() -> bool:
        try:
            failures[:] = _measure(dialog, buttons)
        finally:
            dialog.destroy()
            Gtk.main_quit()
        return False

    GLib.timeout_add(300, inspect)
    Gtk.main()
    if failures:
        sys.stderr.write("FAIL: " + ", ".join(failures) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(_main())
