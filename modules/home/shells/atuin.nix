{ lib, pkgs, ... }:
let
  # Atuin fixed the duplicate Nushell keybinding names in 18.20.1. Retain a
  # compatibility shim only for older packages, then automatically return to
  # Home Manager's upstream integration when the packaged fix is available.
  needsNushellIntegrationShim = lib.versionOlder pkgs.atuin.version "18.20.1";

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
    enableNushellIntegration = !needsNushellIntegrationShim;

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

  programs.nushell.extraConfig = lib.optionalString needsNushellIntegrationShim ''
    source ${atuinNushellConfig}
  '';
}
