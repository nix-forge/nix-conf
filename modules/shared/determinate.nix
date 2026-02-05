# Determinate Nix integration module
#
# Conditionally imports Determinate Nix modules when the input is available.
# For Darwin, also disables nix.enable as required for compatibility.
#
# Required specialArgs: inputs
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

      # nix.enable must be false when using Determinate Nix on Darwin
      nix.enable = false;
    };
}
