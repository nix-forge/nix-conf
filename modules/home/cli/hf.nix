{
  config,
  lib,
  pkgs,
  ...
}:
let
  secretId = "hf-token";
  hasSecret = lib.hasAttrByPath [ "nixSeal" "secrets" secretId ] config;
in
{
  home.packages = [ pkgs.python3Packages.huggingface-hub ];

  home.sessionVariables = lib.optionalAttrs hasSecret {
    HF_TOKEN_PATH = config.nixSeal.secrets.${secretId}.path;
  };
}
