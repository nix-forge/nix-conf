#!@bash@
# shellcheck shell=bash
set -euo pipefail

# UWSM exports the Wayland and Hyprland instance environment to services
# activated by graphical-session.target. Wait for the compositor socket rather
# than relying on a timing-sensitive Hyprland exec-once directive.
ready=0
# The counter is intentionally unused; only the bounded retry count matters.
for _ in $(@seq@ 1 120); do
  if @hyprctl@ monitors -j >/dev/null 2>&1; then
    ready=1
    break
  fi
  @sleep@ 1
done
if [ "$ready" -ne 1 ]; then
  echo "Hyprland did not become ready for the Sunshine virtual output" >&2
  exit 1
fi

# The jq selector must receive its `$output` variable literally.
# shellcheck disable=SC2016
if ! @hyprctl@ monitors -j | @jq@ -e --arg output @headlessOutput@ \
  '.[] | select(.name == $output)' >/dev/null; then
  @hyprctl@ output create headless @headlessOutput@
fi

# The counter is intentionally unused; only the bounded retry count matters.
for _ in $(@seq@ 1 10); do
  # The jq selector must receive its `$output` variable literally.
  # shellcheck disable=SC2016
  if @hyprctl@ monitors -j | @jq@ -e --arg output @headlessOutput@ \
    '.[] | select(.name == $output)' >/dev/null; then
    break
  fi
  @sleep@ 1
done

# The virtual output stays SDR: Sunshine's wlroots screencopy backend cannot
# transport HDR metadata, while genuine Linux HDR capture needs its privileged
# KMS backend and a DRM-attached HDR display.
@hyprctl@ eval 'hl.monitor({ output = "@headlessOutput@", mode = "2562x1656@120", position = "0x0", scale = 1.5, bitdepth = 8, cm = "srgb", supports_wide_color = 0, supports_hdr = 0 })'
