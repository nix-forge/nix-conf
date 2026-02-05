{
  inputs,
  myLib,
  config,
  ...
}:
{
  import = [ inputs.home-manager.flakeModules.home-manager ];

  flake.modules.homeManager = myLib.dir.importFlatWithDirs ../../modules/home { sep = "-"; };
  flake.homeModules = config.flake.modules.homeManager;
}
