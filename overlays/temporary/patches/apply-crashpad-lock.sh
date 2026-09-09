#!/usr/bin/env bash
set -euo pipefail

# Never silently accept an unfamiliar source change. If upstream has this exact
# fix already, leave it alone; the behavioral checks still run during the build.
patch_file=$1
if patch --dry-run --batch --forward --fuzz=0 -p1 <"$patch_file" >/dev/null 2>&1; then
  patch --batch --forward --fuzz=0 -p1 <"$patch_file"
elif patch --dry-run --batch --reverse --fuzz=0 -p1 <"$patch_file" >/dev/null 2>&1; then
  echo "Crashpad report-lock fix is already present; skipping local patch."
else
  echo "Crashpad report-lock source changed; review the fix and run its upstream regression check." >&2
  exit 1
fi
