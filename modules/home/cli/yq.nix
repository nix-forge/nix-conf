{ pkgs, ... }: {
  # Mike Farah's standalone yq uses jq-style expressions for YAML and TOML.
  home.packages = [ pkgs.yq-go ];
}
