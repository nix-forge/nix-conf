{
  # inputs,
  myLib,
  config,
  ...
}:
{
  # import = [ inputs.nix-darwin.flakeModules.nix-darwin ];

  flake.modules.darwin = myLib.dir.importFlatWithDirs ../../modules/darwin { sep = "-"; };
  flake.darwinModules = config.flake.modules.darwin;
}
