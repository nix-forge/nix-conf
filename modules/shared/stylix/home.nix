{
  homeManager = { inputs, ... }: {
    key = "nix-conf/stylix/homeManager";
    _file = __curPos.file;
    imports = [
      (inputs.nix-config-framework.lib.mkSharedModuleSet {
        root = ./.;
        class = "homeManager";
        args = { inherit inputs; };
      }).targets
    ];
  };
}
