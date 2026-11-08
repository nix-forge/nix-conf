# shellcheck shell=bash
# Activation/build supplies variables and functions.
# shellcheck disable=SC2154,SC2329
# Nix store sudo has no setuid bit. Exercise the generated entry
# points that must call the wrapper installed by NixOS activation.
grep -Fq '@desktop_security_wrapperDir@/sudo --non-interactive -- ' @vmPackage@/bin/vm
grep -Fq '@desktop_security_wrapperDir@/sudo --non-interactive -- ' @windowsVmPackage@/bin/windows-vm

xmllint --noout @runtimeDomain@ @installerDomain@

! grep -Eq '__[A-Z0-9_]+__' @windowsBootstrap@
! grep -Eq '__[A-Z0-9_]+__' @windowsBaseline@
grep -Eq "^[$]RecipeFingerprint = '[0-9a-f]{64}'$" @windowsBootstrap@
grep -Eq "^[$]RecipeFingerprint = '[0-9a-f]{64}'$" @windowsBaseline@
test "$(grep -E "^[$]RecipeFingerprint = '[0-9a-f]{64}'$" @windowsBootstrap@)" = \
  "$(grep -E "^[$]RecipeFingerprint = '[0-9a-f]{64}'$" @windowsBaseline@)"

pwsh -NoLogo -NoProfile -NonInteractive -File @parserScript@ @windowsBootstrap@ @windowsBaseline@

shellcheck -s bash @setupScript@
shellcheck -s bash @profileGuard@
shellcheck -s bash @sleepInhibitorHook@
shellcheck -s bash @sleepInhibitorLauncher@
shellcheck -s bash @vmPackage@/bin/vm
shellcheck -s bash @windowsSetupScript@
shellcheck -s bash @windowsVmPackage@/bin/windows-vm
shellcheck -s bash -e SC2034 @setupWindowsVmPackage@/bin/setup-windows-vm
touch "$out"
