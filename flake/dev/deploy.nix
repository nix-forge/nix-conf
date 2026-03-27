{ inputs, self, ... }:
{
  perSystem =
    { system, ... }:
    {
      checks =
        if builtins.hasAttr system inputs.deploy-rs.lib then
          inputs.deploy-rs.lib.${system}.deployChecks (self.deploy or { nodes = { }; })
        else
          { };
    };
}
