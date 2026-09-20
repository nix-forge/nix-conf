{ self, ... }: {
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        desktop-iocost = import ../../tests/nix/desktop-iocost.nix { inherit pkgs; };
        desktop-memory-policy =
          let
            config = self.nixosConfigurations.desktop.config;
            policy = config.system.build.desktopMemoryPolicy;
          in
          pkgs.runCommand "desktop-memory-policy-check"
            {
              nativeBuildInputs = [
                pkgs.gnugrep
                pkgs.shellcheck
              ];
            }
            ''
              shellcheck ${policy}/runner/bin/workstation-task ${policy}/backup-command
              bash -n ${policy}/swap-transition-check ${policy}/preserve-configuration.sh
              shellcheck --shell=bash ${../../hosts/nixos/desktop/local/hardware/guard-swap.sh}

              # Keep the largest temporary allocation off the desktop's memory
              # hierarchy and make the generated scope policy auditable.
              grep -Eq '"useTmpfs"[[:space:]]*:[[:space:]]*false' ${policy}/manifest.json
              grep -Eq '"cleanOnBoot"[[:space:]]*:[[:space:]]*true' ${policy}/manifest.json
              chromium_policy=${policy}/user/app-org.chromium.Chromium-.scope.d/50-oom-policy.conf
              grep -Fx '[Scope]' "$chromium_policy"
              grep -Fx 'MemoryHigh=10G' "$chromium_policy"
              grep -Fx 'MemoryMax=12G' "$chromium_policy"
              grep -Fx 'MemorySwapMax=4G' "$chromium_policy"
              grep -Fx 'OOMPolicy=continue' "$chromium_policy"

              # A manually installed VS Code store symlink must be preserved
              # before Home Manager's collision check, which cannot back it up.
              export HOME="$TMPDIR/home" XDG_STATE_HOME="$TMPDIR/state"
              mkdir -p "$HOME/.config/Code/User" "$HOME/.config/hypr"
              printf 'saved settings' > "$TMPDIR/settings"
              ln -s "$TMPDIR/settings" "$HOME/.config/Code/User/settings.json"
              ln -s /nix/store/example-home-manager-files/hyprland.lua "$HOME/.config/hypr/hyprland.lua"
              run() { :; }
              source ${policy}/preserve-configuration.sh
              test -L "$HOME/.config/Code/User/settings.json"
              test ! -e "$XDG_STATE_HOME"
              run() { "$@"; }
              source ${policy}/preserve-configuration.sh
              test ! -L "$HOME/.config/Code/User/settings.json"
              test -L "$HOME/.config/hypr/hyprland.lua"
              test "$(cat "$XDG_STATE_HOME"/home-manager/conflicts/backup.*/content)" = 'saved settings'
              source ${policy}/preserve-configuration.sh
              test "$(find "$XDG_STATE_HOME" -name original | wc -l)" -eq 1
              touch "$out"
            '';
      };
    };
}
