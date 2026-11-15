# Keep discovery open to new source trees and nested tool configuration, while
# excluding unrelated prose/assets and independently owned submodules.
{ lib, root }:
lib.fileset.toSource {
  inherit root;
  fileset =
    lib.fileset.difference
      (lib.fileset.fileFilter (
        file:
        file.hasExt "py"
        || file.hasExt "pyi"
        || lib.hasSuffix ".py.in" file.name
        || lib.hasSuffix ".pyi.in" file.name
        || builtins.elem file.name [
          "pyproject.toml"
          "ruff.toml"
          ".ruff.toml"
          "ty.toml"
          ".gitignore"
          ".ignore"
        ]
      ) root)
      (
        lib.fileset.unions (
          map (name: root + "/${name}") [
            "pkgs"
            "nix-config-framework"
            "nix-homelab"
            "nix-seal"
          ]
        )
      );
}
