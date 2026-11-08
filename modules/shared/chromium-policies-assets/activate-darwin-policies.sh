# shellcheck shell=bash
install -d -m 0755 "@darwinPolicyDirectory@"
@darwinLegacyManagedPolicyCleanup@
@darwinLegacyExternalExtensionCleanup@
@darwinExtensionPolicyCleanup@
@darwinActivation@
@darwinExtensionManagedPreferencesActivation@
killall cfprefsd 2>/dev/null || true
