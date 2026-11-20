{
  config,
  lib,
  pkgs,
  myLib,
  ...
}:
let
  launcher = (myLib.writers.writeBashTemplate { inherit pkgs; }) {
    name = "zen-session";
    dir = "bin";
    text = ''
      #!@bash@
      # shellcheck shell=bash
      set -euo pipefail
      # Scope placement happens before browser exec, including portal launches. Do
      # not expand URL dollars as environment variables in systemd-run (or UWSM).
      exec @systemdRun@ --user --scope --collect --quiet --expand-environment=no \
        --slice=app-zen.slice --property=OOMPolicy=continue --property=PartOf=graphical-session.target \
        --property=After=graphical-session.target -- @browser@ "$@"
    '';
    replacements = {
      bash = lib.getExe pkgs.bash;
      systemdRun = lib.escapeShellArg (lib.getExe' pkgs.systemd "systemd-run");
      browser = lib.escapeShellArg (lib.getExe' config.programs.zen-browser.package "zen-beta");
    };
  };
  command = lib.getExe launcher;
  entry =
    name:
    pkgs.runCommand name { nativeBuildInputs = [ pkgs.desktop-file-utils ]; } ''
      substitute ${config.programs.zen-browser.package}/share/applications/${name} "$out" \
        --replace-fail 'Exec=zen-beta ' 'Exec=${command} '
      # Every main/action command must use the helper. Fail on upstream launch
      # changes rather than leaving one private-window or URL path uncontained.
      if grep '^Exec=' "$out" | grep -Fv 'Exec=${command} '; then
        echo 'Unexpected Zen desktop launch command' >&2
        exit 1
      fi
      desktop-file-validate "$out"
    '';
  entries = {
    "applications/zen-beta.desktop".source = entry "zen-beta.desktop";
    "applications/zen-beta-private.desktop".source = entry "zen-beta-private.desktop";
  };
in
{
  home.packages = [ launcher ];
  # User entries take precedence for portal launches. Preserve upstream IDs,
  # MIME handlers, labels, field codes and actions; change only the executable.
  # Forwarding a URL to an existing singleton does not move that process.
  xdg.dataFile = entries;

  # One policy for every managed launch and profile; retain reviewed ceilings.
  systemd.user.slices.app-zen = {
    Unit.Description = "Zen browser and content processes";
    Slice = {
      MemoryHigh = "8G";
      MemoryMax = "12G";
      MemorySwapMax = "8G";
      ManagedOOMMemoryPressure = "auto";
    };
  };
}
