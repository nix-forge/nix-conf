{ lib, pkgs, ... }:
let
  # Nushell 0.115 validates binding names. Atuin's generated integration uses
  # the name `atuin` for both Ctrl-R and Up Arrow, which produces a startup
  # warning even though the shortcuts themselves are distinct.
  atuinNushellConfig =
    pkgs.runCommand "atuin-nushell-config.nu" { nativeBuildInputs = [ pkgs.gawk ]; }
      ''
        export HOME="$TMPDIR/home"
        export XDG_CONFIG_HOME="$HOME/.config"
        export XDG_DATA_HOME="$HOME/.local/share"
        mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"

        ${lib.getExe pkgs.atuin} init nu | ${lib.getExe pkgs.gawk} '
          /^[[:space:]]*name: atuin$/ {
            count += 1
            if (count == 1) sub(/atuin$/, "atuin_search")
            else if (count == 2) sub(/atuin$/, "atuin_up")
          }
          { print }
          END {
            if (count != 2) {
              print "expected exactly two Atuin Nushell bindings, found " count > "/dev/stderr"
              exit 1
            }
          }
        ' > "$out"
      '';
in
{
  programs.atuin = {
    enable = true;
    daemon.enable = true;
    enableNushellIntegration = false;

    settings = {
      auto_sync = true;
      sync_frequency = "5m";
      update_check = false;
      search_mode = "fuzzy";
      filter_mode = "global";
      style = "auto";
      show_preview = true;
    };
  };

  programs.nushell.extraConfig = ''
    source ${atuinNushellConfig}
  '';
}
