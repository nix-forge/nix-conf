_: {
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      owned = [
        ../../.github
        ../../flake
        ../../homes
        ../../hosts
        ../../lib
        ../../modules
        ../../overlays
        ../../scripts
        ../../site
        ../../templates
      ];
      retiredLanguage =
        file:
        lib.any file.hasExt [
          "py"
          "pyi"
          "awk"
          "tcl"
          "exp"
          "c"
          "cc"
          "cpp"
        ]
        || lib.hasSuffix ".py.in" file.name;
      retired = lib.fileset.unions (
        map (lib.fileset.fileFilter retiredLanguage) (lib.filter builtins.pathExists owned)
      );
      topLevel = lib.filter (
        name:
        retiredLanguage {
          inherit name;
          hasExt = ext: lib.hasSuffix ".${ext}" name;
        }
      ) (builtins.attrNames (builtins.readDir ../..));
    in
    {
      checks.runtime-source-policy =
        if lib.fileset.toList retired != [ ] || topLevel != [ ] then
          throw "Project-owned Python, C, AWK and Tcl runtime source is retired. Prefer native Nix configuration. Use Swift for macOS programs that benefit from Apple frameworks and Rust for other runtime programs."
        else
          pkgs.runCommand "runtime-source-policy" { } ''
            touch "$out"
          '';
    };
}
