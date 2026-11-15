# shellcheck shell=bash
# shellcheck disable=SC1091,SC2329,SC2154 # The build supplies out; sourced activation invokes run.
shellcheck @policy@/runner/bin/workstation-task @policy@/backup-command
bash -n @policy@/preserve-configuration.sh
python3 @backupCleanupFixture@ @policy@
jq -e '.assertions == []' @policy@/manifest.json >/dev/null

# Keep the largest temporary allocation off the desktop's memory
# hierarchy and make the generated scope policy auditable.
grep -Eq '"useTmpfs"[[:space:]]*:[[:space:]]*false' @policy@/manifest.json
grep -Eq '"cleanOnBoot"[[:space:]]*:[[:space:]]*true' @policy@/manifest.json
chromium_policy=@policy@/user/app-org.chromium.Chromium-.scope.d/50-oom-policy.conf
grep -Fx '[Scope]' "$chromium_policy"
grep -Fx 'MemoryHigh=10G' "$chromium_policy"
grep -Fx 'MemoryMax=12G' "$chromium_policy"
grep -Fx 'OOMPolicy=continue' "$chromium_policy"
chromium_swap_policy=@policy@/user/app-org.chromium.Chromium-.scope.d/70-swap-headroom.conf
grep -Fx '[Scope]' "$chromium_swap_policy"
grep -Fx 'MemorySwapMax=8G' "$chromium_swap_policy"

# A manually installed VS Code store symlink must be preserved
# before Home Manager's collision check, which cannot back it up.
export HOME="/build/fixture-home" XDG_STATE_HOME="$TMPDIR/state"
mkdir -p "$HOME/.config/Code/User" "$HOME/.config/hypr"
printf 'saved settings' >"$TMPDIR/settings"
ln -s "$TMPDIR/settings" "$HOME/.config/Code/User/settings.json"
ln -s /nix/store/example-home-manager-files/hyprland.lua "$HOME/.config/hypr/hyprland.lua"
run() { :; }
source @preserveConfigurationFixture@
test -L "$HOME/.config/Code/User/settings.json"
test ! -e "$XDG_STATE_HOME"
run() { "$@"; }
source @preserveConfigurationFixture@
test ! -L "$HOME/.config/Code/User/settings.json"
test -L "$HOME/.config/hypr/hyprland.lua"
test "$(cat "$XDG_STATE_HOME"/home-manager/conflicts/backup.*/content)" = 'saved settings'
source @preserveConfigurationFixture@
test "$(find "$XDG_STATE_HOME" -name original | wc -l)" -eq 1
touch "$out"
