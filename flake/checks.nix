{ self, ... }:
{
  perSystem =
    { pkgs, system, ... }@args:
    {
      checks = {
        default =
          let
            name = "check-store-errors";
            hashName = builtins.substring 0 32 (builtins.hashString "sha256" name);
          in
          pkgs.writeShellApplication {
            inherit name;
            text = ''
              while nix flake check --no-build |& grep "is not valid" >/tmp/invalid-${hashName}; do
                path=$(</tmp/invalid-${hashName} awk -F\' '{print $2}')
                echo "Repairing $path"
                sudo nix-store --repair-path "$path" >/dev/null
              done
            '';
          };

        pre-commit-check = self.inputs.pre-commit-hooks.lib.${system}.run {
          src = ./../.;
          hooks = import ./hooks.nix args;
        };
      };
    };
}
