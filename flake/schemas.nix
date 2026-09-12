{ inputs, ... }:
let
  attrsetSchema =
    {
      doc,
      what,
      childWhat,
    }:
    {
      version = 1;
      inherit doc;
      inventory = output: {
        inherit what;
        evalChecks.isAttributeSet = builtins.isAttrs output;
        children = builtins.mapAttrs (_: value: {
          what = childWhat;
          evalChecks.isAttributeSet = builtins.isAttrs value;
        }) output;
      };
    };
in
{
  flake.schemas = inputs.flake-schemas.exportedSchemas // {
    featureCatalog = {
      version = 1;
      doc = "Bounded reusable feature inventory and support requirements; observed validation is recorded separately.";
      inventory = output: {
        what = "feature inventory";
        evalChecks.valid = output.schema == 1 && builtins.isList output.features;
      };
    };
    validationManifest = {
      version = 1;
      doc = "Required native build, activation, runtime and recovery evidence; this inventory is not a pass record.";
      inventory = output: {
        what = "validation requirements";
        evalChecks.valid = output.schema == 1 && builtins.isList output.checks;
      };
    };
    ciChecks = inputs.flake-schemas.exportedSchemas.checks;
    lintChecks = inputs.flake-schemas.exportedSchemas.checks;

    deploy = attrsetSchema {
      doc = "deploy-rs nodes; full node and activation validation is provided by checks.x86_64-linux.deploy-schema and deploy-activate.";
      what = "deploy-rs configuration";
      childWhat = "deploy-rs node collection";
    };

    modules = attrsetSchema {
      doc = "nix-config-framework module catalog; exported module leaves also receive isFunctionOrAttrs flake checks.";
      what = "module catalog";
      childWhat = "platform module catalog";
    };

    nixSeal = attrsetSchema {
      doc = "Public nix-seal administrator catalog. Private identities and plaintext are never flake outputs.";
      what = "public nix-seal policy catalog";
      childWhat = "nix-seal catalog collection";
    };
  };
}
