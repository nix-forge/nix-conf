# shellcheck shell=bash
test "$(systemctl is-active fixture-writer.service)" = inactive
cp /var/lib/recovery-fixture/live "$RECOVERY_EXPORT/record"
