"""Check serialized settings and repeated Hyprlang blocks independently."""

import json
import os
import re
import shlex
from pathlib import Path

import tomllib

root = Path(os.environ["FILES"])
with (root / "noctalia.toml").open("rb") as source:
    shell = tomllib.load(source)
assert shell["shell"]["font_family"] == os.environ["FONT"]
assert shell["shell"]["offline_mode"] is False
assert shell["shell"]["launch_apps_custom_command"] == "uwsm app -- $CMD"
assert shell["theme"]["pure_black_dark"] is True
assert shell["theme"]["custom_palette"] == "Stylix"
assert shell["bar"]["default"]["start"] == ["launcher", "workspaces", "active_window"]
assert shell["osd"]["kinds"]["media"] is False
assert shell["lockscreen"]["enabled"] is False
palette = json.loads((root / "palette.json").read_text())
assert palette["dark"]["mPrimary"] == "#abcdef"
assert palette["dark"]["mSurface"] == "#123456"
assert palette["dark"]["terminal"]["bright"]["white"] == "#123456"
notifications = json.loads((root / "swaync.json").read_text())
assert notifications["widgets"] == ["title", "dnd", "notifications", "mpris", "volume"]
assert notifications["timeout-critical"] == 0
assert notifications["widget-config"]["volume"] == {"label": "Volume"}


def _hyprconf(name: str) -> dict[str, str | list[dict[str, str]]]:
    """Parse the subset of Hyprlang used in these configurations.

    Returns:
        Top-level strings and lists of section dictionaries, in source order.

    """
    result: dict[str, str | list[dict[str, str]]] = {}
    section: dict[str, str] | None = None
    for raw_line in (root / name).read_text().splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if match := re.fullmatch(r"(\w+)\s*\{", line):
            assert section is None, line
            section = {}
            sections = result.setdefault(match[1], [])
            assert isinstance(sections, list)
            sections.append(section)
        elif line == "}":
            assert section is not None
            section = None
        else:
            key, value = (part.strip() for part in line.split("=", 1))
            target = result if section is None else section
            assert key not in target, key
            target[key] = value
    assert section is None
    return result


idle = _hyprconf("hypridle.conf")
enable = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'"
disable = "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'"
assert idle == {
    "general": [
        {
            "lock_cmd": "pidof hyprlock || hyprlock",
            "inhibit_sleep": "3",
            "before_sleep_cmd": "loginctl lock-session",
            "after_sleep_cmd": enable,
            "on_lock_cmd": "printf 'locked'",
            "on_unlock_cmd": enable,
        }
    ],
    "listener": [
        {
            "timeout": "300",
            "ignore_inhibit": "false",
            "on-timeout": "loginctl lock-session",
        },
        {"timeout": "330", "on-timeout": disable, "on-resume": enable},
        {
            "timeout": "30",
            "ignore_inhibit": "true",
            "condition_retry": "5",
            "condition_cmd": 'pgrep -u "$(id -u)" -x hyprlock > /dev/null',
            "on-timeout": disable,
            "on-resume": enable,
        },
        {"timeout": "900", "on-timeout": "systemctl suspend"},
    ],
}
background_idle = _hyprconf("hypridle-background.conf")
background_general = background_idle["general"]
assert isinstance(background_general, list)
assert background_general[0]["ignore_wayland_inhibit"] == "true"
background_listeners = background_idle["listener"]
assert isinstance(background_listeners, list)
assert [listener["timeout"] for listener in background_listeners] == [
    "300",
    "330",
    "30",
    "900",
]
screen_condition = background_listeners[0]["condition_cmd"]
screen_arguments = shlex.split(screen_condition)
assert screen_arguments[0].endswith("/bin/desktop-idle-inhibit-check")
assert screen_arguments[1:] == ["screen", "--", "chatgpt"]
assert background_listeners[0]["ignore_inhibit"] == "false"
assert background_listeners[1]["condition_cmd"] == screen_condition
assert background_listeners[2] == idle["listener"][2]
assert background_listeners[3]["condition_cmd"].endswith(
    "/bin/desktop-idle-inhibit-check suspend"
)
assert all(listener["condition_retry"] == "5" for listener in background_listeners)
assert _hyprconf("hyprpaper.conf") == {
    "splash": "false",
    "ipc": "on",
    "wallpaper": [
        {
            "monitor": "DP-1",
            "path": "/home/tester/first wallpaper.png",
            "fit_mode": "contain",
        },
        {
            "monitor": "DP-2",
            "path": "/home/tester/second wallpaper.png",
            "fit_mode": "contain",
        },
    ],
}
clipboard = dict(
    line.split(" ", 1) for line in (root / "cliphist.conf").read_text().splitlines()
)
assert clipboard == {
    "max-items": "42",
    "max-store-size": "5MiB",
    "max-dedupe-search": "100",
    "preview-width": "120",
}
