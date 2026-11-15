# Host-owned secret paths and API endpoints for reusable native website login jobs.
{ config, lib, ... }:
let
  names = [
    "sonarr"
    "radarr"
    "lidarr"
    "prowlarr"
    "bazarr"
  ];
  enabled = lib.filter (name: config.homelab.apps.${name}.enable) names;
  secret = name: field: config.nixSeal.secrets."homelab-${name}-${field}".path;
  endpoint =
    name:
    if name == "bazarr" then
      "http://127.0.0.1:${toString config.services.bazarr.settings.general.port}"
    else
      "http://${if name == "prowlarr" then config.homelab.apps.prowlarr.bindAddress else "127.0.0.1"}:${
        toString config.services.${name}.settings.server.port
      }";
in
{
  homelab.integration.webAuth = lib.genAttrs enabled (name: {
    url = endpoint name;
    usernameFile = secret name "username";
    passwordFile = secret name "password";
    apiKeyFile = secret name "api-key";
    after = [
      "nix-seal-activate.service"
      "homelab-integrate-${name}.service"
    ];
    requires = [ "nix-seal-activate.service" ];
    allowedCIDRs = [
      "127.0.0.0/8"
      "${config.homelab.vpn.namespace.bindAddress}/32"
    ];
  });
}
