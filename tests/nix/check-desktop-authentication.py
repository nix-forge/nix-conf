"""Check the generated desktop authentication boundary and shared appearance."""

from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

import tomllib

MAX_GREETER_IDLE_SECONDS = 60
MIN_TEXT_CONTRAST = 4.5
SRGB_LINEAR_THRESHOLD = 0.04045


def require(condition: bool, message: str) -> None:
    """Report a violated authentication requirement.

    Raises:
        ValueError: The generated policy violates the named requirement.

    """
    if not condition:
        raise ValueError(message)


def contrast(foreground: str, background: str) -> float:
    """Calculate the WCAG contrast ratio of two opaque sRGB colors.

    Returns:
        The foreground/background contrast ratio, from one to twenty-one.

    """

    def luminance(value: str) -> float:
        channels = [int(value.lstrip("#")[i : i + 2], 16) / 255 for i in (0, 2, 4)]
        return sum(
            (
                channel / 12.92
                if channel <= SRGB_LINEAR_THRESHOLD
                else ((channel + 0.055) / 1.055) ** 2.4
            )
            * weight
            for channel, weight in zip(channels, (0.2126, 0.7152, 0.0722), strict=True)
        )

    low, high = sorted((luminance(foreground), luminance(background)))
    return (high + 0.05) / (low + 0.05)


def check_native_controls(
    lock: str, panel_width: int, input_height: int, scale: float
) -> None:
    """Check native input geometry and reject external command-based controls."""
    require(
        "hide_cursor=false" in lock, "Native pointer submission needs a visible cursor"
    )
    require("ignore_empty_input=true" in lock, "Reject empty unlock submissions")
    submit_shapes = [
        block
        for block in re.findall(r"shape \{([^}]+)\}", lock)
        if "submit_input=true" in block
    ]
    require(
        len(submit_shapes) == 1, "Exactly one native submit target must be configured"
    )
    require("onclick=" not in lock, "Lock controls must not execute shell commands")
    require(
        "text_align=left" in lock and "dots_center=false" in lock,
        "Use consistent left-aligned password feedback",
    )
    input_block = next(iter(re.findall(r"input-field \{([^}]+)\}", lock)))
    input_width = panel_width - 32 - 8 - input_height
    dimensions = re.search(r"size=([\d.]+),\s*([\d.]+)", input_block)
    outline = re.search(r"outline_thickness=([\d.]+)", input_block)
    require(
        dimensions is not None and outline is not None, "Input geometry is explicit"
    )
    assert dimensions is not None
    assert outline is not None
    border = float(outline[1])
    require(
        math.isclose(float(dimensions[1]) + 2 * border, input_width * scale)
        and math.isclose(float(dimensions[2]) + 2 * border, input_height * scale),
        "Password outer bounds must match login geometry, including the outline",
    )

    card = next(
        block
        for block in re.findall(r"shape \{([^}]+)\}", lock)
        if "submit_input=true" not in block
    )
    card_size = re.search(r"size=([\d.]+),\s*([\d.]+)", card)
    card_border = re.search(r"border_size=([\d.]+)", card)
    require(
        card_size is not None and card_border is not None, "Card geometry is explicit"
    )
    assert card_size is not None
    assert card_border is not None
    require(
        math.isclose(
            float(card_size[1]) + 2 * float(card_border[1]),
            panel_width * scale,
        ),
        "Card outer width must include its border",
    )


def check_typography(
    lock: str, font_scale: float, output_scale: float, clock_format: str
) -> None:
    """Compare fractional text sizes against the shell's shared role sizes."""
    clock = next(
        block
        for block in re.findall(r"label \{([^}]+)\}", lock)
        if clock_format in block
    )
    require(
        f'size="{round(48 * font_scale * output_scale * 0.75 * 1024)}"' in clock,
        "Clock text must preserve fractional Pango sizing and desktop font scale",
    )
    for token in ("$LAYOUT$CAPSLOCK", "$AUTHCHECK", "$AUTHFAIL"):
        caption = next(
            block for block in re.findall(r"label \{([^}]+)\}", lock) if token in block
        )
        require(
            f'size="{round(13 * font_scale * output_scale * 0.75 * 1024)}"' in caption,
            "Keyboard and authentication status must use the desktop caption size",
        )


def main() -> None:
    """Read actual generated files, including their rendered PAM rules."""
    files = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))

    def text(name: str) -> str:
        return Path(files[name]).read_text(encoding="utf-8")

    greeter = tomllib.loads(text("greeter"))
    greetd = tomllib.loads(text("greetd"))
    shell = tomllib.loads(text("shell"))
    lock = text("lock")
    idle = text("idle")

    require("initial_session" not in greetd, "Login must not bypass authentication")
    require(
        greetd["default_session"]["user"] == "greeter",
        "Use the dedicated greeter account",
    )
    require(
        "noctalia-greeter-session" in greetd["default_session"]["command"],
        "Start the graphical greeter session",
    )
    require(
        not greeter["auth"]["allow_empty_password"],
        "Do not submit empty login passwords",
    )
    require(
        0 < greeter["idle"]["timeout"] <= MAX_GREETER_IDLE_SECONDS,
        "Protect the unattended login display",
    )
    require(
        greeter["session"]["default"] == "Hyprland (uwsm-managed)",
        "Retain the UWSM session",
    )

    for pam_file in ("loginPam", "lockPam"):
        auth = [
            line for line in text(pam_file).splitlines() if line.startswith("auth ")
        ]
        require(
            not any("pam_fprintd" in line for line in auth),
            "This desktop must use password PAM without a fingerprint reader",
        )
        require(
            not any("nullok" in line for line in auth),
            "Null password authentication must be disabled",
        )
        require(
            any("pam_gnome_keyring" in line for line in auth),
            "Keep the password keyring hook",
        )
        require(
            any("pam_faildelay" in line and "3000000" in line for line in auth),
            "Keep a bounded failure delay",
        )
        require(
            any("pam_deny" in line for line in auth),
            "Failed credentials must reach a deny rule",
        )

    appearance = greeter["appearance"]
    font_scale = appearance["font_scale"]
    require(
        math.isclose(font_scale, shell["accessibility"]["ui_scale"], abs_tol=1e-6),
        "Authentication text must use the desktop's font scale",
    )
    require(appearance["password_style"] == "default", "Use consistent masked input")  # ruff: ignore[hardcoded-password-string] - Masking enum, not a credential.
    require("hide_input=false" in lock, "Locker must show masked password feedback")
    require(
        re.search(r"fingerprint\s*\{\s*enabled=false\s*\}", lock) is not None,
        "Disable the desktop locker's fingerprint backend",
    )
    require("$FPRINTPROMPT" not in lock, "Do not display prompts for absent hardware")
    require(
        re.search(r'foreground="#(?!#)', lock) is None,
        "Escape markup color hashes so Hyprlang does not truncate the field text",
    )
    check_native_controls(
        lock,
        appearance["panel_width"],
        appearance["input_height"],
        greeter["output"]["scale"],
    )
    require(
        f"font_family={appearance['font_family']}" in lock,
        "Authentication fonts must agree",
    )
    check_typography(
        lock, font_scale, greeter["output"]["scale"], appearance["clock_time_format"]
    )
    require(
        f"outer_color=rgb({appearance['palette']['secondary'].lstrip('#')})" in lock,
        "Use the desktop's secondary focus color",
    )
    for role in ("on_surface", "on_surface_variant"):
        require(
            contrast(
                appearance["palette"][role], appearance["palette"]["surface_variant"]
            )
            >= MIN_TEXT_CONTRAST,
            f"Small authentication text in {role} must remain readable",
        )
    require(appearance["clock_time_format"] in lock, "Authentication clocks must agree")
    require(appearance["clock_date_format"] in lock, "Authentication dates must agree")
    for role in ("surface", "surface_variant", "primary", "on_surface"):
        require(
            appearance["palette"][role].lstrip("#").lower() in lock.lower(),
            f"Locker must use the {role} role",
        )
    require(
        "$AUTHFAIL" in lock and "$AUTHCHECK" in lock,
        "Expose authentication feedback outside the password field",
    )
    require("$LAYOUT$CAPSLOCK" in lock, "Expose native keyboard state")
    require(
        "update:1000" not in lock, "Keyboard status must not poll external commands"
    )
    require("desktop-session-lock lock" in idle, "Scope lock launches to their display")
    require("inhibit_sleep=3" in idle, "Wait for lock acknowledgement before suspend")
    require(
        "before_sleep_cmd=loginctl lock-session" in idle, "Suspend must request a lock"
    )
    require("clipboard-clear" in idle, "Keep clipboard clearing at the lock boundary")
    require(
        not re.search(r"pidof\s+hyprlock", idle),
        "Do not gate on another session's process",
    )
    actions = shell["shell"]["session"]["actions"]
    require(
        any(
            row.get("label") == "Lock"
            and "loginctl" in row.get("command", "")
            and "lock-session" in row["command"]
            for row in actions
        ),
        "Expose the external locker in shell actions",
    )
    require(not shell["lockscreen"]["enabled"], "Only Hyprlock may own the lock")
    sys.stdout.write("Desktop authentication and appearance policy passed\n")


if __name__ == "__main__":
    main()
