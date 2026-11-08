# Entry points and sibling imports must share one physical store directory.
{ pkgs }:
pkgs.runCommand "hyprland-guest-python" { } ''
  mkdir -p "$out"
  install -m444 ${./lifetime/compositor_lifecycle.py} "$out/compositor_lifecycle.py"
  install -m444 ${./lifetime/lifetime_cases.py} "$out/lifetime_cases.py"
  install -m444 ${./compositor_events.py} "$out/compositor_events.py"
  install -m444 ${../waits.py} "$out/waits.py"
  install -m444 ${./subsurface_rounding.py} "$out/verify-rounding.py"
''
