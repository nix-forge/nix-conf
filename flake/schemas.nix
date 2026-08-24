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
