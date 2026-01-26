{ lib, pkgs, ... }:
{
  name,
  package,
  wayland ? true,
}:
let
  # Create the desktop file to define the session inside of a directory
  desktopFile =
    let
      sessionsType = if wayland then "wayland-sessions" else "xsessions";
      script = ''
        ${lib.getExe package} &> /dev/null
      '';
    in
    pkgs.writeTextDir "share/${sessionsType}/${name}.desktop" ''
      [Desktop Entry]
      Name=${name}
      Exec=${pkgs.writeShellScript "${name}-session" script}
      Type=Application
    '';

  # Create a symlink to the desktop file in the format that NixOS expects
  # NOTE: To understand symlinkJoin read https://ryantm.github.io/nixpkgs/builders/trivial-builders/#trivial-builder-symlinkJoin
  session = pkgs.symlinkJoin {
    # This is name under which the system link will be stored in the Nix Store
    name = "${name}-session";
    # The binary which will be stored under the system link
    # NOTE: This is a list because there can be more than one type desktop configuration per type like wayland vs xorg
    #       However, this function will just create a new system link for each config defined so name accordingly if necessary
    paths = [ desktopFile ];
    # Pass Extra Arguments
    # DOCS: https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/x11/display-managers/default.nix
    # NOTE: The providedSessions should contain strings of the names of the sessions
    #       This is list should match with the list from the paths. However, this function will only use one item.
    passthru.providedSessions = [ name ];
  };
in
{
  services.displayManager.sessionPackages = [ session ];
}
