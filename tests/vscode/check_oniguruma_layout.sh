#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
  echo "usage: $0 VSCODE_APP" >&2
  exit 2
fi

app=$1
wasm="$app/node_modules.asar.unpacked/vscode-oniguruma/release/onig.wasm"

if [[ ! -r "$wasm" ]]; then
  echo "VS Code cannot read its TextMate tokenizer at $wasm" >&2
  exit 1
fi

echo "VS Code TextMate tokenizer is readable at $wasm"
