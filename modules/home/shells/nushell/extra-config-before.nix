{ lib, ... }:
let
  esepDirListToList = var: ''
    "${var}" :{
      from_string: { |s|
        $s
        | default ""
        | split row (char esep)
        | where ($it | str length) > 0
        | path expand --no-symlink
      }
      to_string: { |v|
        $v
        | path expand --no-symlink
        | str join (char esep)
      }
    }
  '';
in
{
  programs.nushell.extraConfig = lib.mkBefore (
    ''
      $env.ENV_CONVERSIONS = {
        ${esepDirListToList "Path"}
        ${esepDirListToList "PATH"}
        ${esepDirListToList "TERMINFO_DIRS"}
        ${esepDirListToList "XDG_CONFIG_DIRS"}
        ${esepDirListToList "XDG_DATA_DIRS"}
        ${esepDirListToList "XCURSOR_PATH"}
      }
    ''
    # NU_LIB_DIRS
    # -----------
    # Directories in this constant are searched by the
    # `use` and `source` commands.
    #
    # By default, the `scripts` subdirectory of the default configuration
    # directory is included:
    + ''
      const NU_LIB_DIRS = [
        ($nu.default-config-dir | path join 'scripts') # add <nushell-config-dir>/scripts
        ($nu.data-dir | path join 'completions') # default home for nushell completions
      ]
    ''
  );
}
