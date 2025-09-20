{ self, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      devShells.default =
        let
          inherit (self.checks.${system}.git-hooks-check) shellHook enabledPackages;
        in
        pkgs.mkShellNoCC {
          buildInputs = enabledPackages;
          packages = [ ];

          shellHook = '''' + shellHook;
        };
    };
}
