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
          nativeBuildInputs = [
            inputs.nix-seal.packages.${system}.nix-seal
            pkgs.age
            pkgs.jq
            pkgs.openssh
          ];
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

            # Disposable end-to-end dogfood. All identities and values are
            # generated inside the isolated check; no repository secret or
            # private key is read, and only public reports are copied to $out.
            e2e="$TMPDIR/nix-seal-e2e"
            mkdir -p "$e2e/secrets/services/example" "$e2e/templates/services"
            umask 077
            nix-seal key generate --identity-out "$e2e/admin.agekey" > "$e2e/admin.recipient"
            nix-seal key generate --identity-out "$e2e/server.agekey" > "$e2e/server.recipient"
            nix-seal key generate-signing --key-out "$e2e/signing.key" > "$e2e/signing.public"
            admin_recipient="$(tr -d '\n' < "$e2e/admin.recipient")"
            server_recipient="$(tr -d '\n' < "$e2e/server.recipient")"
            signing_recipient="$(tr -d '\n' < "$e2e/signing.public")"
            runtime_owner="$(id -un)"
            runtime_group="$(id -gn)"
            printf '%s\n' 'token={{nix-seal:token}}' > "$e2e/templates/services/example.conf"
            printf '%s\n' \
              'schema = "nix-seal.plan.v1"' \
              "" \
              '[identities.admin]' \
              'kind = "administrator"' \
              "public = \"$admin_recipient\"" \
              "" \
              '[identities.server]' \
              'kind = "target"' \
              "public = \"$server_recipient\"" \
              "" \
              '[identities.release]' \
              'kind = "signer"' \
              "public = \"$signing_recipient\"" \
              "" \
              '[targets.server]' \
              "kind = \"${if pkgs.stdenv.isDarwin then "darwin" else "nixOs"}\"" \
              "system = \"${system}\"" \
              'identity = "server"' \
              "" \
              '[approvalPolicies.release]' \
              'threshold = 1' \
              'signers = ["release"]' \
              "" \
              '[secrets."services/example/token"]' \
              'source = "secrets/services/example/token.age"' \
              'consumers = ["server"]' \
              'administrators = ["admin"]' \
              'approvalPolicy = "release"' \
              "" \
              '[secrets."services/example/token".runtime]' \
              "owner = \"$runtime_owner\"" \
              "group = \"$runtime_group\"" \
              'mode = "0400"' \
              "" \
              '[templates."services/example/config"]' \
              'source = "templates/services/example.conf"' \
              "" \
              '[templates."services/example/config".placeholders.token]' \
              'secret = "services/example/token"' \
              'encoding = "utf8"' \
              "" \
              '[templates."services/example/config".runtime]' \
              "owner = \"$runtime_owner\"" \
              "group = \"$runtime_group\"" \
              'mode = "0400"' \
              > "$e2e/nix-seal.toml"
            nix-seal plan --toml "$e2e/nix-seal.toml" --output "$e2e/plan.v1.json"
            nix-seal check --toml "$e2e/nix-seal.toml" --repository-root "$e2e"
            head -c 48 /dev/urandom | base64 | tr -d '\n' > "$e2e/input.secret"
            expected_hash="$(sha256sum "$e2e/input.secret" | cut -d' ' -f1)"
            nix-seal secret create \
              --plan "$e2e/plan.v1.json" \
              --repository-root "$e2e" \
              --secret services/example/token \
              --identity "$e2e/admin.agekey" < "$e2e/input.secret"
            nix-seal check --toml "$e2e/nix-seal.toml" --repository-root "$e2e" --deep
            actual_hash="$(nix-seal secret reveal \
              --plan "$e2e/plan.v1.json" \
              --repository-root "$e2e" \
              --secret services/example/token \
              --identity "$e2e/admin.agekey" | sha256sum | cut -d' ' -f1)"
            test "$expected_hash" = "$actual_hash"
            nix-seal provision \
              --plan "$e2e/plan.v1.json" \
              --repository-root "$e2e" \
              --target server \
              --generation 1 \
              --signing-key "$e2e/signing.key" \
              --identity "$e2e/admin.agekey" \
              --cache-root "$e2e/cache" \
              --execute --json > "$e2e/provision.json"
            cache_key="$(jq -r '.artifacts[0].cacheKey' "$e2e/provision.json")"
            source_hash="$(jq -r '.artifacts[0].sourceCiphertextHash' "$e2e/provision.json")"
            test "$cache_key" != null
            test "$source_hash" != null
            nix-seal cache export --root "$e2e/cache" --destination "$e2e/export"
            nix-seal cache import --root "$e2e/imported-cache" --source "$e2e/export"
            artifact="$e2e/imported-cache/artifacts/$cache_key"
            runtime_root="$e2e/runtime"
            jq -n \
              --arg plan "$e2e/plan.v1.json" \
              --arg runtime "$runtime_root" \
              --arg target "server" \
              --arg ciphertext "$artifact/ciphertext.age" \
              --arg envelope "$artifact/manifest.dsse.json" \
              --arg source_hash "$source_hash" \
              --arg template "$e2e/templates/services/example.conf" \
              --arg owner "$runtime_owner" \
              --arg group "$runtime_group" \
              '{
                schema: "nix-seal.activation.v2",
                runtimeRoot: $runtime,
                runtimeGeneration: null,
                plan: $plan,
                targetId: $target,
                phase: "activation",
                allowedClockSkew: 300,
                artifacts: [{
                  ciphertext: $ciphertext,
                  envelope: $envelope,
                  secretId: "services/example/token",
                  sourceCiphertextHash: $source_hash,
                  artifactGeneration: 1,
                  phase: "activation",
                  mode: "0400",
                  owner: $owner,
                  group: $group
                }],
                templates: [{
                  source: $template,
                  templateId: "services/example/config",
                  phase: "activation",
                  placeholders: {token: {secretId: "services/example/token", encoding: "utf8"}},
                  mode: "0400",
                  owner: $owner,
                  group: $group
                }],
                postSwitch: null
              }' > "$e2e/activation.json"
            nix-seal activate \
              --spec "$e2e/activation.json" \
              --identity "$e2e/server.agekey" \
              --json > "$e2e/activation-report.json"
            test -f "$runtime_root/current/services/example/token"
            test -f "$runtime_root/current/templates/services/example/config"
            cmp "$e2e/input.secret" "$runtime_root/current/services/example/token"
            printf 'token=' > "$e2e/expected-template"
            cat "$e2e/input.secret" >> "$e2e/expected-template"
            printf '\n' >> "$e2e/expected-template"
            cmp "$e2e/expected-template" "$runtime_root/current/templates/services/example/config"

            # Synthetic side-by-side secretctl migration. This exercises the
            # actual legacy SSH-recipient decrypt/re-encrypt path without
            # opening any repository identity or ciphertext.
            legacy_root="$e2e"
            mkdir -p "$legacy_root/secrets/IanHollow"
            umask 077
            ssh-keygen -q -t ed25519 -N "" -f "$e2e/legacy-ssh-key"
            legacy_recipient="$(ssh-keygen -y -f "$e2e/legacy-ssh-key" | tr -d '\n')"
            printf '%s' 'legacy-migration-canary' > "$e2e/legacy-plaintext"
            age -r "$legacy_recipient" -o "$legacy_root/secrets/IanHollow/legacy.age" "$e2e/legacy-plaintext"
            legacy_source_hash="$(sha256sum "$legacy_root/secrets/IanHollow/legacy.age" | cut -d' ' -f1)"
            jq -n \
              --arg recipient "$legacy_recipient" \
              '{
                version: 1,
                groups: {IanHollow: [$recipient]},
                targets: {"host:nixos:server": {
                  type: "host",
                  groups: ["IanHollow"],
                  publicKey: $recipient,
                  recipients: [$recipient]
                }},
                secrets: {"IanHollow.legacy": {
                  id: "IanHollow.legacy",
                  group: "IanHollow",
                  scope: "host",
                  selector: null,
                  agenixName: "legacy",
                  file: "secrets/IanHollow/legacy.age",
                  recipients: [$recipient],
                  consumers: ["host:nixos:server"]
                }}
              }' > "$e2e/legacy-secret-index.json"
            nix-seal migrate secretctl \
              --index "$e2e/legacy-secret-index.json" \
              --plan-output "$e2e/secretctl-plan.v1.json" \
              --target-system 'host:nixos:server=${system}' \
              --canonical-source-prefix migrated-secretctl \
              --administrator "migration-admin=$admin_recipient" \
              --signer "release=$signing_recipient" \
              --json > "$e2e/secretctl-plan-report.json"
            jq -e '
              .candidatePlan != null
            ' "$e2e/secretctl-plan-report.json" >/dev/null
            jq -e '
              .secrets["ianhollow.legacy"].delivery == "rekeyed"
              and (.secrets["ianhollow.legacy"].administrators | length) == 1
              and .secrets["ianhollow.legacy"].source == "migrated-secretctl/secrets/IanHollow/legacy.age"
            ' "$e2e/secretctl-plan.v1.json" >/dev/null
            nix-seal migrate secretctl \
              --index "$e2e/legacy-secret-index.json" \
              --repository-root "$e2e" \
              --destination migrated-secretctl \
              --identity "$e2e/legacy-ssh-key" \
              --verification-identity "$e2e/admin.agekey" \
              --recipient "$admin_recipient" \
              --json > "$e2e/legacy-migration-dry-run.json"
            test ! -e "$e2e/migrated-secretctl/secrets/IanHollow/legacy.age"
            nix-seal migrate secretctl \
              --index "$e2e/legacy-secret-index.json" \
              --repository-root "$e2e" \
              --destination migrated-secretctl \
              --identity "$e2e/legacy-ssh-key" \
              --verification-identity "$e2e/admin.agekey" \
              --recipient "$admin_recipient" \
              --execute \
              --json > "$e2e/legacy-migration.json"
            migrated_ciphertext="$e2e/migrated-secretctl/secrets/IanHollow/legacy.age"
            test -f "$migrated_ciphertext"
            nix-seal check \
              --nix-plan "$e2e/secretctl-plan.v1.json" \
              --deep \
              --repository-root "$e2e"
            age -d -i "$e2e/admin.agekey" "$migrated_ciphertext" > "$e2e/migrated-plaintext"
            cmp "$e2e/legacy-plaintext" "$e2e/migrated-plaintext"
            test "$legacy_source_hash" = "$(sha256sum "$legacy_root/secrets/IanHollow/legacy.age" | cut -d' ' -f1)"
            jq -e '.dryRun == true and .source == "secretctl"' "$e2e/legacy-migration-dry-run.json" >/dev/null
            jq -e '.dryRun == false and .source == "secretctl"' "$e2e/legacy-migration.json" >/dev/null
            jq -n \
              --arg expectedHash "$expected_hash" \
              --arg actualHash "$actual_hash" \
              --arg cacheKey "$cache_key" \
              --arg legacySourceHash "$legacy_source_hash" \
              --arg activationReport "$(jq -c '{activated,changed,secretCount,templateCount}' "$e2e/activation-report.json")" \
              '{schema:"nix-seal.parent-dogfood.v1", expectedHash:$expectedHash, actualHash:$actualHash, cacheKey:$cacheKey, legacySourceHash:$legacySourceHash, migration:{dryRun:true,executed:true,source:"secretctl"}, activation:($activationReport|fromjson)}' \
              > "$out/end-to-end.json"
        '';
  };
}
