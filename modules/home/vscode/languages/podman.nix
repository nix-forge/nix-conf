{ pkgs, inputs, ... }:
let
  extensions = (pkgs.extend inputs.nix4vscode.overlays.default).nix4vscode;
in
{
  programs.vscode.profiles.default = {
    extensions = extensions.forVscode [
      "ms-azuretools.vscode-containers"
      "ms-vscode-remote.remote-containers"
    ];

    userSettings = {
      "[dockerfile]" = {
        "editor.defaultFormatter" = "ms-azuretools.vscode-containers";
        "editor.tabSize" = 2;
      };
      "[dockercompose]" = {
        "editor.defaultFormatter" = "redhat.vscode-yaml";
        "editor.tabSize" = 2;
      };

      "containers.containerClient" = "com.microsoft.visualstudio.containers.podman";
      "dev.containers.dockerPath" = "podman";
      "dev.containers.dockerComposePath" = "podman-compose";
    };
  };
}
