{
  enablePodman ? false,
}:
{
  lib,
  pkgs,
  inputs,
  config,
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
    ];

  programs.vscode.profiles.default.userSettings =
    {
      "[dockerfile]" = {
        "editor.defaultFormatter" = "ms-azuretools.vscode-containers";
        "editor.tabSize" = 4;
      };
    }
    // lib.optionalAttrs enablePodman {
      "containers.containerClient" = "com.microsoft.visualstudio.containers.podman";
    };
}
