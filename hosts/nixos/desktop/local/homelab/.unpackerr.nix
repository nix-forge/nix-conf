{
  arrUrl,
  apiKeyFile,
  downloadsDir,
}:
let
  services = [
    "sonarr"
    "radarr"
  ];
  credentialName = service: "${service}-api";
  settingsFor = service: [
    {
      url = arrUrl service;
      api_key = "filepath:/run/credentials/unpackerr.service/${credentialName service}";
      paths = [ downloadsDir ];
      protocols = "torrent";
      delete_orig = false;
    }
  ];
in
{
  settings = builtins.listToAttrs (
    map (service: {
      name = service;
      value = settingsFor service;
    }) services
  );
  loadCredentials = map (service: "${credentialName service}:${apiKeyFile service}") services;
}
