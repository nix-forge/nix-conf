{ lib }:
# Both representations must retain the same root-only token and canonical source.
{
  nixSeal,
  owner,
  group,
  expectedSource,
  originalSource ? expectedSource,
}:
let
  name = "nix-access-tokens";
  runtimeFiles = nixSeal.secrets // nixSeal.templates;
  runtime = runtimeFiles.${name} or null;
  private = file: file.owner == owner && file.group == group && file.mode == "0400";
in
runtime != null
&& private runtime
&& (
  if builtins.hasAttr name nixSeal.secrets then
    originalSource != null && nixSeal.secrets.${name}.source == originalSource
  else
    builtins.hasAttr name nixSeal.templates
    && lib.all (
      placeholderDef:
      let
        field = nixSeal.secrets.${placeholderDef.secret};
      in
      private field && field.source == expectedSource
    ) (builtins.attrValues nixSeal.templates.${name}.placeholders)
    && nixSeal.templates.${name}.placeholders != { }
)
