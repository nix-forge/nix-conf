# Both representations must retain the same root-only token and canonical source.
{
  lib,
  nixSeal,
  owner,
  group,
}:
let
  name = "nix-access-tokens";
  original = "secrets/ianhollow/users/ianmh/nix-access-tokens.age";
  runtimeFiles = nixSeal.secrets // nixSeal.templates;
  runtime = runtimeFiles.${name} or null;
  private = file: file.owner == owner && file.group == group && file.mode == "0400";
in
runtime != null
&& private runtime
&& (
  if builtins.hasAttr name nixSeal.secrets then
    nixSeal.secrets.${name}.source == original
  else
    builtins.hasAttr name nixSeal.templates
    && lib.all (
      placeholderDef:
      let
        field = nixSeal.secrets.${placeholderDef.secret};
      in
      private field && field.source == "secrets/ianhollow/users/ianmh/fields/${placeholderDef.secret}.age"
    ) (builtins.attrValues nixSeal.templates.${name}.placeholders)
    && nixSeal.templates.${name}.placeholders != { }
)
