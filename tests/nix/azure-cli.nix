{ pkgs, inputs }:
let
  selected = pkgs.extend (import ../../overlays { inherit inputs; });
  azure = selected.azure-cli.withExtensions [ selected.azure-cli.extensions.azure-devops ];
  fabric =
    pkgs.lib.findSingle (package: (package.pname or "") == "fabric")
      (throw "Azure CLI has no Fabric dependency")
      (throw "Azure CLI has multiple Fabric dependencies")
      azure.propagatedBuildInputs;
  invoke =
    pkgs.lib.findSingle (package: (package.pname or "") == "invoke")
      (throw "Fabric has no Invoke dependency")
      (throw "Fabric has multiple Invoke dependencies")
      fabric.propagatedBuildInputs;
  sshtunnel =
    pkgs.lib.findSingle (package: (package.pname or "") == "sshtunnel")
      (throw "Azure CLI has no SSH tunnel dependency")
      (throw "Azure CLI has multiple SSH tunnel dependencies")
      azure.propagatedBuildInputs;
  python = fabric.pythonModule;
in
assert fabric.version == "3.2.3";
assert toString pkgs.path == toString inputs.nixpkgs;
assert invoke.version == "3.0.3";
assert !(fabric.meta.broken or false);
assert pkgs.python3Packages.invoke.version == "3.0.3";
assert !(sshtunnel.__noChroot or false);
pkgs.runCommand "azure-cli-compatible-invoke" { } ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  export AZURE_CORE_COLLECT_TELEMETRY=false
  export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
  export PYTHONPATH="${python.pkgs.makePythonPath azure.propagatedBuildInputs}:${azure}/${python.sitePackages}"
  ${python}/bin/python ${./scripts/azure_cli_compatibility.py}
  ${azure}/bin/az version > "$TMPDIR/azure-version.json"
  ${azure}/bin/az webapp ssh --help > "$TMPDIR/webapp-ssh-help"
  ${azure}/bin/az devops --help > "$TMPDIR/devops-help"
  ${azure}/bin/az extension list --query '[].name' --output tsv | grep -Fx azure-devops
  touch "$out"
''
