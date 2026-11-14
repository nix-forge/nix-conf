# shellcheck shell=bash
install -m 0644 @target_source@ "@darwinPolicyDirectory@/@target_bundleId@.plist"
chown root:wheel "@darwinPolicyDirectory@/@target_bundleId@.plist"
