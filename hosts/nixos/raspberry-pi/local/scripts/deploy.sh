#!/usr/bin/env bash
set -euo pipefail

mode="${1:?expected build or deploy}"
flake_root="${2:?expected flake path}"

case "$mode" in
build) activation=(--dry-activate) ;;
deploy) activation=() ;;
*)
  echo "expected build or deploy, got: $mode" >&2
  exit 2
  ;;
esac

if [[ "$(hostname -s)" != desktop ]]; then
  echo "Build the Pi system on desktop, where the AArch64 builder is configured." >&2
  exit 1
fi

# Admit ARM emulation only for this Pi invocation, preserving existing platforms.
# Keep the vendor cache available to deploy-rs's child Nix commands before
# the updated desktop cache policy has been activated.
export NIX_CONFIG="${NIX_CONFIG:-}
extra-extra-platforms = aarch64-linux
extra-substituters = https://nixos-raspberrypi.cachix.org
extra-trusted-public-keys = nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="

kernel="$(nix eval --raw --accept-flake-config \
  "$flake_root#nixosConfigurations.raspberry-pi.config.boot.kernelPackages.kernel.outPath")"

# Check the remote cache even when the path is already local, then copy its
# signed output if needed. A cache miss must stop before the ARM build begins.
nix path-info --store https://nixos-raspberrypi.cachix.org "$kernel" >/dev/null
nix copy --from https://nixos-raspberrypi.cachix.org \
  --extra-trusted-public-keys \
  'nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=' \
  "$kernel"

# The repository's focused checks and dry activation cover this target. The
# default deploy-rs preflight evaluates unrelated desktop and Darwin checks.
nix run --accept-flake-config "$flake_root#raspberry-pi-deploy" -- \
  --skip-checks "${activation[@]}" "$flake_root#raspberry-pi"
