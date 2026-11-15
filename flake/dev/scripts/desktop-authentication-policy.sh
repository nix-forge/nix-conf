# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
for pam in @loginPam@ @lockPam@; do
  ! grep -Eq '^auth .*nullok' "$pam"
  grep -Eq '^auth .*pam_deny[.]so' "$pam"
done
touch "$out"
