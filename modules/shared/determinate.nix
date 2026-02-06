{ inputs, ... }:
{
  nixos =
    { ... }:
    {
      imports = [ inputs.determinate.nixosModules.default ];
    };

  darwin =
    { ... }:
    {
      imports = [ inputs.determinate.darwinModules.default ];
      determinateNix.enable = true;
      nix.enable = false;
    };

  homeManager = {
    ## Workaround: Disable HM manual to suppress Determinate Nix warning
    ## about options.json referencing store paths without proper context.
    ## Upstream issue: https://github.com/nix-community/home-manager/issues/7935
    manual.manpages.enable = false;
  };
}
