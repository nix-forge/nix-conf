{
  config,
  lib,
  pkgs,
  ...
}:
let
  direnvCacheDirectory = "${config.xdg.cacheHome}/direnv";
  direnvLayoutDirectory = "${direnvCacheDirectory}/layouts";
  sha256sum = lib.getExe' pkgs.coreutils "sha256sum";
in
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;

    # Keep reproducible layout data out of source trees. The full path hash is
    # required because nix-direnv's profile names do not identify the project.
    stdlib = ''
      direnv_layout_dir() {
        local project_hash
        project_hash="$(printf '%s' "$PWD" | ${sha256sum})"
        project_hash="''${project_hash%% *}"
        printf '%s/%s\n' ${lib.escapeShellArg direnvLayoutDirectory} "$project_hash"
      }
    '';
  };

  # nix-direnv evaluates cached profile files as shell code. Protect the
  # common parent so layouts created with the user's normal umask remain
  # inaccessible to other local users.
  home.activation.prepareDirenvCache = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe' pkgs.coreutils "install"} -d -m 0700 \
      ${lib.escapeShellArg direnvCacheDirectory} \
      ${lib.escapeShellArg direnvLayoutDirectory}
  '';
}
