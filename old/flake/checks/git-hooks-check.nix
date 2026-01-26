{ self, ... }:
{
  perSystem =
    { system, ... }@args:
    {
      checks.git-hooks-check = self.inputs.git-hooks.lib.${system}.run {
        src = ../../.;
        hooks = import ../hooks.nix args;
      };
    };
}
