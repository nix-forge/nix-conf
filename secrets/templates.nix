# Apply the reviewed public inventory only after all fields for an entry exist.
# This lets ciphertext authoring precede provisioning without breaking evaluation.
{
  lib,
  repositoryRoot,
  scope,
  secrets,
}:
let
  inventory = builtins.fromJSON (builtins.readFile ./templates.json);
  sourceFor = name: secrets.${name}.source or "secrets/${scope}/${name}.age";
  candidates = lib.mapAttrs (name: _: inventory.${sourceFor name} or null) secrets;
  active = lib.filterAttrs (
    name: entry:
    entry != null
    && sourceFor name == entry.original
    && lib.all (field: builtins.pathExists (repositoryRoot + "/${field.source}")) (
      builtins.attrValues entry.fields
    )
  ) candidates;
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
}
