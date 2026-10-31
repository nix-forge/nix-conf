let
  root = toString ../../..;
  flake = (builtins.getAttr "getFlake" builtins) ("git+file://" + root + "?submodules=1");
  pkgs = import flake.inputs.nixpkgs { system = "aarch64-darwin"; };
  selected = pkgs.extend (import ../../default.nix { inputs = flake.inputs; });
  azure = selected.azure-cli.withExtensions [ selected.azure-cli.extensions.azure-devops ];
  ssh =
    pkgs.lib.findSingle (package: (package.pname or "") == "sshtunnel")
      (throw "Azure CLI has no SSH tunnel dependency")
      (throw "Azure CLI has multiple SSH tunnel dependencies")
      azure.propagatedBuildInputs;
in
assert !(ssh.__noChroot or false);
{
  inherit ssh;
  cli = import ../../../tests/nix/azure-cli.nix {
    inherit pkgs;
    inputs = flake.inputs;
  };
  metadata = {
    nixpkgsRevision = flake.inputs.nixpkgs.rev;
    azureVersion = azure.version;
    sshVersion = ssh.version;
    sshSourceHash = ssh.src.outputHash;
    strictSandbox = !(ssh.__noChroot or false);
    localNetworking = ssh.__darwinAllowLocalNetworking or false;
    disabledTests = ssh.disabledTests or [ ];
  };
}
