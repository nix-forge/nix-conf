{ lib, ... }: {
  mkTemplates =
    # Template entries always use their field ciphertexts. Missing fields fail
    # evaluation instead of falling back to a whole-configuration ciphertext.
    {
      repositoryRoot,
      scope,
      secrets,
      inventoryFiles,
    }:
    let
      inventory = lib.foldl' (
        result: file:
        result
        // lib.mapAttrs (
          _: entry:
          (removeAttrs entry [ "template" ])
          // {
            content = builtins.readFile (dirOf file + "/${entry.template}");
          }
        ) (builtins.fromJSON (builtins.readFile file))
      ) { } inventoryFiles;
      sourceFor = name: secrets.${name}.source or "secrets/${scope}/${name}.age";
      candidates = lib.mapAttrs (name: _: inventory.${sourceFor name} or null) secrets;
      active = lib.mapAttrs (
        name: entry:
        assert lib.assertMsg (lib.all (field: builtins.pathExists (repositoryRoot + "/${field.source}")) (
          builtins.attrValues entry.fields
        )) "Missing ciphertext for nix-seal template ${name}";
        entry
      ) (lib.filterAttrs (name: entry: entry != null && sourceFor name == entry.original) candidates);
      fields = lib.foldlAttrs (
        result: name: entry:
        result // lib.mapAttrs (_: field: (removeAttrs secrets.${name} [ "source" ]) // field) entry.fields
      ) { } active;
      templates = lib.mapAttrs (
        name: entry:
        removeAttrs secrets.${name} [
          "source"
          "serviceCredentials"
        ]
        // {
          # Public text only. Avoid a platform-specific derivation during plan evaluation.
          source = builtins.toFile "${name}.template" entry.content;
          placeholders = lib.mapAttrs (_: secret: {
            inherit secret;
            encoding = "utf8";
          }) entry.placeholders;
        }
      ) active;
    in
    {
      secrets = removeAttrs secrets (builtins.attrNames active) // fields;
      inherit templates;
    };
}
