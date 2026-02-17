let
  lockData = builtins.fromJSON (builtins.readFile ../../flake.lock);
  rootInputs = lockData.nodes.root.inputs;

  resolveNodeRef =
    ref:
    if builtins.isString ref then
      ref
    else if builtins.isList ref then
      resolvePath ref
    else
      throw "Unsupported flake.lock input reference type";

  resolvePath =
    path:
    builtins.foldl' (
      nodeName: segment:
      let
        node = lockData.nodes.${nodeName};
      in
      resolveNodeRef node.inputs.${segment}
    ) lockData.root path;

  isRootFlakeInput =
    name:
    if !(builtins.hasAttr name rootInputs) then
      false
    else
      let
        nodeName = resolveNodeRef rootInputs.${name};
      in
      lockData.nodes.${nodeName}.flake or true;

  partitionInputNames =
    flakeFile:
    let
      partitionFlake = import flakeFile;
      declaredInputs = partitionFlake.inputs or { };
      isFlakeInput =
        name:
        let
          spec = declaredInputs.${name};
        in
        if builtins.isAttrs spec then spec.flake or true else true;
    in
    builtins.filter isFlakeInput (builtins.attrNames declaredInputs);

  nixosPartitionInputs = partitionInputNames ../../flake/nixos/flake.nix;
  darwinPartitionInputs = partitionInputNames ../../flake/darwin/flake.nix;

  allowedByClass =
    class: name:
    isRootFlakeInput name
    || (class == "nixos" && builtins.elem name nixosPartitionInputs)
    || (class == "darwin" && builtins.elem name darwinPartitionInputs);

  mkRegistry =
    {
      lib,
      inputs,
      self,
      class,
    }:
    let
      # Register direct root flake inputs from flake.lock, plus class-specific
      # partition inputs (darwin/nixos only).
      flakeInputs = lib.filterAttrs (
        name: value: allowedByClass class name && builtins.isAttrs value && value ? outputs
      ) inputs;
      registryFlakes = flakeInputs // {
        inherit self;
      };
    in
    lib.mapAttrs (_: flake: { inherit flake; }) registryFlakes;
in
{
  nixos =
    {
      inputs,
      self,
      lib,
      ...
    }:
    {
      nix.registry = mkRegistry {
        inherit lib inputs self;
        class = "nixos";
      };
    };

  darwin =
    {
      inputs,
      self,
      lib,
      config,
      ...
    }:
    let
      registry = mkRegistry {
        inherit lib inputs self;
        class = "darwin";
      };
      usingDeterminateNix = lib.hasAttr "determinateNix" config && config.determinateNix.enable;
    in
    lib.mkMerge [
      (lib.mkIf (!usingDeterminateNix) { nix.registry = registry; })
      (lib.mkIf usingDeterminateNix { determinateNix.registry = registry; })
    ];

  homeManager =
    {
      inputs,
      self,
      lib,
      config,
      ...
    }:
    {
      nix.registry = lib.mkIf (config.nix.package != null) (mkRegistry {
        inherit lib inputs self;
        class = "homeManager";
      });
    };
}
