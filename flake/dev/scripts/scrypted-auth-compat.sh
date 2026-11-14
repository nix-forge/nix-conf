# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
cp @scryptedScripts@/scrypted-api.cjs ./scrypted-api.cjs
cp @scryptedScripts@/scrypted-auth.cjs ./scrypted-auth.cjs
cp @scryptedScripts@/scrypted-auth.test.cjs ./scrypted-auth.test.cjs
@scrypted@/bin/scrypted-node \
  ./scrypted-auth.test.cjs \
  @serverRoot@
touch "$out"
