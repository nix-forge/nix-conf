#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
printf 'Scanning Git history for credentials.\n'
gitleaks git --config .gitleaks-history.toml --redact --no-banner

# Scan exactly the committed root tree, including unchanged files. Generated
# development outputs and submodule worktrees are checked separately.
snapshot=$(mktemp -d)
trap 'rm -rf "$snapshot"' EXIT
git archive --format=tar HEAD | tar -xf - -C "$snapshot"
printf 'Scanning the committed tree for credentials and publication metadata.\n'
(
  cd "$snapshot"
  gitleaks dir . --config .gitleaks.toml --redact --no-banner
)
