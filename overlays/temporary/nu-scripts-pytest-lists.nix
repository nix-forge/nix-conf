_: {
  reason = "The pytest completion uses semicolons where Nushell requires list separators.";
  upstream = "https://github.com/nushell/nu_scripts/blob/3ffc5aa43194bb4d5295dec9fbf0a18b3a2dddfc/custom-completions/pytest/pytest-completions.nu#L10-L11";
  removal = "The selected upstream pytest completion parses without replacing its list separators.";
  reviewedRevision = "02c087f3fe673c9e317f206a627cb6b910336dbe";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace custom-completions/pytest/pytest-completions.nu \
          --replace-fail '["w"; "a"]' '["w", "a"]' \
          --replace-fail '["plain"; "rewrite"]' '["plain", "rewrite"]'
      '';
    });
}
