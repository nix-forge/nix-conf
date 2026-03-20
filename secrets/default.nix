{ myLib }:
let
  inherit (builtins)
    attrNames
    filter
    listToAttrs
    readDir
    substring
    ;
  collectAgeSecrets = myLib.dir.collectBySuffix "file" ".age" "secrets";
  entries = readDir ./.;

  groupDirs = filter (name: entries.${name} == "directory" && substring 0 1 name != ".") (
    attrNames entries
  );
in
listToAttrs (
  map (group: {
    name = group;
    value = collectAgeSecrets (./. + "/${group}");
  }) groupDirs
)
