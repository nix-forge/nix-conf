{
  config,
  lib,
  pkgs,
  ...
}:
let
  hasSecret = lib.hasAttrByPath [ "age" "secrets" "hf_token" ] config;
in
{
  home.packages = [ pkgs.python3Packages.huggingface-hub ];

  home.sessionVariables = lib.optionalAttrs hasSecret {
    HF_TOKEN_PATH = config.age.secrets.hf_token.path;
  };
}
