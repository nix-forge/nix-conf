{
  enablePodman ? false,
}:
{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { inherit inputs; };
    in
    with extensions.preferNixpkgsThenPreRelease;
    [
      ms-azuretools.vscode-containers
      ms-vscode-remote.remote-containers
    ]
    ++ lib.optionals enablePodman [ dreamcatcher45.podmanager ];

  programs.vscode.profiles.default.userSettings = {
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
}
