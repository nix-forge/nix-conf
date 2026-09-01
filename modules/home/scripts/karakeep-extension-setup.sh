#!@bash@
# shellcheck shell=bash
set -euo pipefail

cat <<'EOF'
Karakeep local server:
  @localUrl@

The Firefox and Zen Karakeep extension is force-installed by policy. Open the
extension options, set the server address above, then sign in or paste an API
key from Karakeep. The extension stores its settings in browser sync storage,
so the API key is intentionally not managed from Nix.
EOF
@openCommand@ @localUrl@ >/dev/null 2>&1 || true
