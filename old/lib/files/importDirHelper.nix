{ lib, ... }:
dir:
{
  # List of files and directories to remove from the result
  filter,
  # Function to applt to apply filter
  filter_fn ? ({ name, isNix, ... }: isNix && !(builtins.elem name filter)),
  # import directory if it has a default.nix file
  importDirDefault ? false,
  ...
}:
let
  inherit (import ./default.nix { inherit lib; }) nixDirEntries;
  importDirHelper = (import ./importDirHelper.nix) { inherit lib; };
  val_fn =
    entry:
    if (importDirDefault && entry.hasDefault) || entry.isNixFile then
      import entry.path
    else if entry.hasNixFiles then
      importDirHelper entry.path { inherit filter filter_fn importDirDefault; }
    else
      abort "No nix files found in directory. Not filtered properly.";
in
nixDirEntries dir filter_fn val_fn
