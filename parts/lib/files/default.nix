{ lib, ... }:
{
  mkDirEntry = import ./mkDirEntry.nix { inherit lib; };
  mkDirEntries = import ./mkDirEntries.nix { inherit lib; };
  nixDirEntries = import ./nixDirEntries.nix { inherit lib; };
  importRec = import ./importRec.nix { inherit lib; };
  importDirRec = import ./importDirRec.nix { inherit lib; };
  importDirFlat = import ./importDirFlat.nix { inherit lib; };
}
