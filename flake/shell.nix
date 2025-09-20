{ self, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      devShells.default =
        let
          inherit (self.checks.${system}.pre-commit-check) shellHook enabledPackages;
        in
        pkgs.mkShellNoCC {
          buildInputs = enabledPackages;
          packages = [ ];

          shellHook = '''' + shellHook;
        };
    };
}
