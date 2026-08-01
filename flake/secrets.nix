{
  config,
  inputs,
  myLib,
  ...
}:
let
  allSecrets = import ../secrets { inherit myLib; };
  inventory = config.nixConfigFramework.inventory;
  secretIndex = myLib.secrets.mkSecretctlIndex {
    secretsTree = allSecrets;
    homeConfigs = inventory.homes;
    hostConfigs = inventory.hosts;
  };
in
{
  flake.secretIndex = secretIndex;
  perSystem = { pkgs, system, ... }: {
    checks.nix-seal-dogfood =
      pkgs.runCommand "nix-seal-parent-dogfood"
        {
          nativeBuildInputs = [ inputs.nix-seal.packages.${system}.nix-seal ];
          secretIndex = pkgs.writeText "nix-conf-secret-index.json" (builtins.toJSON secretIndex);
        }
        ''
            dogfood="$TMPDIR/nix-seal-dogfood"
            mkdir -p "$dogfood/templates/services"
            cp ${inputs.nix-seal}/nix-seal.example.toml "$dogfood/nix-seal.toml"
          printf '%s\n' 'token={{nix-seal:token}}' \
            > "$dogfood/templates/services/example.conf"
            mkdir -p "$out"
            nix-seal plan \
              --toml "$dogfood/nix-seal.toml" \
              --output "$out/plan.v1.json"
            nix-seal check \
              --toml "$dogfood/nix-seal.toml" \
              --repository-root "$dogfood"
            nix-seal schema --kind plan > "$out/plan-v1.schema.json"
            nix-seal recipients \
              --plan "$out/plan.v1.json" \
              --secret services/example/token > "$out/recipients.json"
            nix-seal migrate secretctl \
              --index "$secretIndex" \
              --json > "$out/secretctl-migration.json"
            test -s "$out/plan.v1.json"
            test -s "$out/plan-v1.schema.json"
            test -s "$out/recipients.json"
            test -s "$out/secretctl-migration.json"
        '';
  };
}
