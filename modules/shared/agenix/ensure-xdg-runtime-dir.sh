# shellcheck disable=SC2148
# ensure-xdg-runtime-dir.sh — Ensure @xdgRuntimeDir@ exists on macOS/Darwin.
#
# Per the XDG Base Directory Specification (v0.8):
#   - @xdgRuntimeDir@ MUST be owned by the user
#   - @xdgRuntimeDir@ MUST have Unix access mode 0700
#   - @xdgRuntimeDir@ MUST be on a local filesystem
#   - @xdgRuntimeDir@ lifetime MUST be bound to the user being logged in
#   - Files in @xdgRuntimeDir@ MUST NOT survive reboot
#
# On macOS /private/tmp is cleaned on reboot, satisfying the lifetime and
# reboot-survival requirements. This script creates and validates the
# directory with the required ownership and permissions.

set -euo pipefail

readonly XDG_RUNTIME="@xdgRuntimeDir@"
readonly OWNER="@username@"

# ── Symlink attack mitigation ────────────────────────────────────────────────
# A symlink at the target path could redirect writes to an attacker-controlled
# location. Bail out immediately if the path is a symlink.
if [ -L "${XDG_RUNTIME}" ]; then
  printf 'FATAL: @xdgRuntimeDir@ path is a symlink: %s\n' "${XDG_RUNTIME}" >&2
  exit 1
fi

# ── Create the directory with restrictive permissions ────────────────────────
# Set umask first so mkdir inherits 0700 from the start — there is no window
# where the directory is world-readable.
umask 077
mkdir -p "${XDG_RUNTIME}"

# Explicitly enforce permissions and ownership even if the directory already
# existed with incorrect mode or owner.
chmod 700 "${XDG_RUNTIME}"
chown "${OWNER}" "${XDG_RUNTIME}"

# ── Post-creation validation ─────────────────────────────────────────────────
if [ ! -d "${XDG_RUNTIME}" ]; then
  printf 'FATAL: @xdgRuntimeDir@ is not a directory: %s\n' "${XDG_RUNTIME}" >&2
  exit 1
fi

# Verify the expected user owns the directory — another user's directory with
# identical path (e.g. leftover from a different UID) must not be reused.
actual_owner="$(stat -c '%U' "${XDG_RUNTIME}")"
if [ "${actual_owner}" != "${OWNER}" ]; then
  printf 'FATAL: @xdgRuntimeDir@ is owned by "%s", expected "%s": %s\n' \
    "${actual_owner}" "${OWNER}" "${XDG_RUNTIME}" >&2
  exit 1
fi
