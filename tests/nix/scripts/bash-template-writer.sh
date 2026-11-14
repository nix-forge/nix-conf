# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
for script in @lib_getExe_bin@ @single@ @libexec@/libexec/writer-probe; do
  test -x "$script"
  test "$(grep -c '^#!' "$script")" = 1
  test "$(head -n 1 "$script")" = '#! @lib_getExe_pkgs_bashNonInteractive@'
  "$script" 'argument with spaces' >actual
  printf '%s\n' "$expected" 'argument with spaces' >expected-output
  cmp actual expected-output
  "$script" "" $'line\nbreak' -- -n >actual
  printf '%s\n' "$expected" "" $'line\nbreak' -- -n >expected-output
  cmp actual expected-output
done
test "$(@lib_getExe_relaxed@)" = continued
# Building a program that exits nonzero proves validation doesn't run it.
test -x @lib_getExe_parseOnly@
@lib_getExe_pathReplacement@
@lib_getExe_isolatedRuntime@
# The Nix workload launcher dispatches by the invoked symlink's name.
ln -s @alias@ writer-alias
test "$(./writer-alias)" = writer-alias
touch "$out"
