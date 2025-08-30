profileName:
{
  enablePodman ? false,
}:
{ lib, pkgs, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions =
      with extensions.preferNixpkgsThenPreRelease;
      [
        ms-azuretools.vscode-containers
        ms-vscode-remote.remote-containers
      ]
      ++ lib.optionals enablePodman [ dreamcatcher45.podmanager ];

    userSettings = {
      "[dockerfile]" = {
        "editor.defaultFormatter" = "ms-azuretools.vscode-containers";
        "editor.tabSize" = 4;
      };
    }
    // lib.optionalAttrs enablePodman {
      "containers.containerClient" = "com.microsoft.visualstudio.containers.podman";
      "dev.containers.dockerPath" = "podman";
      "dev.containers.dockerComposePath" = "podman-compose";
    };
  };
}
