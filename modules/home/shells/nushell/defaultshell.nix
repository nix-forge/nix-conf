{ lib, pkgs, ... }: {
  # Use an absolute executable path so GUI applications do not need to resolve
  # `nu` through their inherited PATH.
  home.sessionVariables.SHELL = lib.getExe pkgs.nushell;
}
