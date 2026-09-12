{
  inputs,
  self,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    let
      checkPython = import ./quality-python.nix { inherit pkgs; };
      # Test the sources produced by the real Nix declarations, including
      # public-value substitution. No source-template inventory is maintained.
      secretTemplateSources =
        self.nixosConfigurations.desktop.config.home-manager.users.ianmh.nixSeal.templates
        // {
          inherit (self.nixosConfigurations.desktop.config.nixSeal.templates) flakehub-netrc;
        };
    in
    {
      checks = {
        secret-templates =
          assert import ../../tests/secrets/template-policy.nix { inherit (pkgs) lib; };
          (import ../../tests/python-check.nix { inherit pkgs; }) {
            name = "secret-template-tests";
            files = [
              ../../tests/secrets
              ../../homes/macbook-pro-m4/local/nix-seal
            ];
            testPaths = [ "tests/secrets/test_public_templates.py" ];
            selection = "nix_integration";
            nativeBuildInputs = [
              pkgs.git
              inputs.nix-seal.packages.${pkgs.stdenv.hostPlatform.system}.default
            ];
            prepare = ''
              mkdir -p compiled-templates
              ${pkgs.lib.concatStringsSep "\n" (
                pkgs.lib.mapAttrsToList (
                  name: template:
                  pkgs.lib.escapeShellArgs [
                    "cp"
                    (toString template.renderedSource)
                    "compiled-templates/${name}.template"
                  ]
                ) secretTemplateSources
              )}
            '';
          };

        python-quality =
          pkgs.runCommand "python-quality"
            {
              nativeBuildInputs = [
                checkPython
                pkgs.ruff
                pkgs.ty
              ];
            }
            ''
              set -euo pipefail

              work_directory="$TMPDIR/python-quality-source"
              mkdir "$work_directory"
              cp -R ${inputs.self.outPath}/. "$work_directory"
              chmod -R u+w "$work_directory"
              cd "$work_directory"

              export RUFF_CACHE_DIR="$TMPDIR/ruff-cache"
              export PYTHONPYCACHEPREFIX="$TMPDIR/python-pycache"

              # Use each project's checked-in Ruff configuration, including the
              # submodules. Explicit --config would override their own rules.
              ruff check --no-fix .
              ruff format --check .

              # `--project .` makes ty discover [tool.ty] in this exact copied
              # pyproject.toml. Use Nix Python rather than an impure developer
              # virtualenv so the result is reproducible on every system.
              ty check --project . --python ${checkPython}/bin/python3

              # Cover every Python-bearing top-level source tree, including the
              # MacBook local-control resolver and its unittest fixture. Bytecode
              # is redirected outside the source tree above.
              python3 -m compileall -q homes modules scripts tests pkgs

              touch "$out"
            '';

        # Detect a canary even inside paths with narrowly scoped exceptions.
        gitleaks-policy =
          pkgs.runCommand "gitleaks-policy"
            {
              nativeBuildInputs = [
                pkgs.gitleaks
                pkgs.git
              ];
            }
            ''
              set -euo pipefail
              bash ${../../tests/privacy/check-publication-policy.sh} ${../../.gitleaks.toml} \
                ${../../.github/scripts/scan-publication.sh}
              fixture="$TMPDIR/fixture"
              mkdir -p "$fixture"
              scan_fixture() {
                # Match the repository-relative paths produced by Git scans.
                (
                  cd "$fixture"
                  gitleaks dir . "$@"
                )
              }
              for policy in ${../../.gitleaks.toml} ${../../pkgs/.gitleaks.toml} ${../../nix-seal/.gitleaks.toml}; do
                for filename in ordinary.txt .nix-seal/public.nix nix-seal.lock.json \
                  pkgs/by-name/sp/spotify-spotx/source.nix crates/nix-seal-cli/src/main.rs; do
                  mkdir -p "$fixture/$(dirname "$filename")"
                  # Exercise a provider token and the generic rule used by the
                  # public-hash exceptions. Neither fixture is an operational key.
                  for prefix in ghp_ ""; do
                    printf 'password = "%s%s"\n' "$prefix" 'aB3dE6gH9jK2mN5pQ8sT1vW4yZ7bC0eF3hI6' > "$fixture/$filename"
                    status=0
                    scan_fixture --config "$policy" --redact --no-banner > "$TMPDIR/scan.log" 2>&1 || status=$?
                    if [ "$status" -ne 1 ]; then
                      printf 'Expected credential detection for %s under %s, got exit %s\n' "$filename" "$policy" "$status" >&2
                      cat "$TMPDIR/scan.log" >&2
                      exit 1
                    fi
                  done
                  rm "$fixture/$filename"
                done
              done

              # The public download exception covers only the complete URL
              # assignment. Another JWT on that line must remain detectable.
              jwt_header=$(printf '{"alg":"HS256","typ":"JWT"}' | base64 | tr -d '=\n')
              jwt_payload=$(printf '{"sub":"checker-policy-canary"}' | base64 | tr -d '=\n')
              jwt_signature=aB3dE6gH9jK2mN5pQ8sT1vW4yZ7bC0eF3hI6
              jwt="$jwt_header.$jwt_payload.$jwt_signature$jwt_signature"
              for policy in ${../../.gitleaks.toml} ${../../pkgs/.gitleaks.toml}; do
                filename="$fixture/pkgs/by-name/sp/spotify-spotx/source.nix"
                printf 'url = "https://upgrade.scdn.co/upgrade/client/osx-arm64/spotify-autoupdate-1.2.3.tbz?fauth=%s";\n' "$jwt" > "$filename"
                scan_fixture --config "$policy" --redact --no-banner
                sed -i "s/;$/; token=\"$jwt\"/" "$filename"
                status=0
                scan_fixture --config "$policy" --redact --no-banner > "$TMPDIR/scan.log" 2>&1 || status=$?
                if [ "$status" -ne 1 ]; then
                  echo "A download-URL exception hid another JWT on the same line" >&2
                  cat "$TMPDIR/scan.log" >&2
                  exit 1
                fi
                rm "$filename"
              done

              # A permitted test value must not exempt another credential on the
              # same source line. Keep this separate from the single-token probes.
              allowed_canary=$(printf cli-activation-canary | base64)
              printf 'password=%s\n' "$allowed_canary" > "$fixture/crates/nix-seal-cli/src/main.rs"
              scan_fixture --config ${../../nix-seal/.gitleaks.toml} --redact --no-banner
              printf 'password=%s; password="%s"\n' "$allowed_canary" \
                'aB3dE6gH9jK2mN5pQ8sT1vW4yZ7bC0eF3hI6' > "$fixture/crates/nix-seal-cli/src/main.rs"
              status=0
              scan_fixture --config ${../../nix-seal/.gitleaks.toml} \
                --redact --no-banner > "$TMPDIR/scan.log" 2>&1 || status=$?
              if [ "$status" -ne 1 ]; then
                echo "A test-value exception hid another credential on the same line" >&2
                cat "$TMPDIR/scan.log" >&2
                exit 1
              fi
              touch "$out"
            '';

      }
      // pkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
        clamav-special-files = import ../../tests/nix/clamav-special-files.nix { inherit pkgs; };
        clamav-runtime = import ../../tests/nix/clamav-runtime.nix { inherit pkgs; };
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        macos-home-dry-run =
          let
            fakeDockutil = pkgs.writeShellScriptBin "dockutil" ''
              printf 'dockutil must not execute during a dry run\n' >&2
              exit 99
            '';
            fakeFinderFavorites = pkgs.writeShellScriptBin "finder-favorites" ''
              printf 'finder-favorites must not execute during a dry run\n' >&2
              exit 99
            '';
            dryRunHome = inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                ../../modules/home/macos
                {
                  home = {
                    username = "check-user";
                    homeDirectory = "/Users/check-user";
                    stateVersion = "25.05";
                  };
                  macos.dockItems = {
                    enable = true;
                    mode = "authoritative";
                    package = fakeDockutil;
                    persistentApps = [ { app = "/Applications/Missing Test.app"; } ];
                  };
                  macos.finderFavorites = {
                    enable = true;
                    mode = "reconcile";
                    allowDeprecatedBackend = true;
                    package = fakeFinderFavorites;
                    entries = [
                      {
                        id = "dry-run";
                        label = "Dry Run";
                        path = "/Users/check-user/Dry Run";
                        onMissing = "createDirectory";
                      }
                    ];
                  };
                }
              ];
            };
            dockActivation = pkgs.writeText "macos-dock-dry-run" dryRunHome.config.home.activation.syncDockItems.data;
            finderActivation = pkgs.writeText "macos-finder-favorites-dry-run" dryRunHome.config.home.activation.syncFinderFavorites.data;
            finderConfiguration = dryRunHome.config.xdg.configFile."finder-favorites/config.json".source;
          in
          pkgs.runCommand "macos-home-dry-run"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.gnugrep
              ];
            }
            ''
              set -euo pipefail
              export DRY_RUN=1
              run() {
                printf 'DRY-RUN %s\n' "$*"
              }
              verboseEcho() {
                printf '%s\n' "$*"
              }
              export -f run verboseEcho

              bash ${dockActivation} > "$TMPDIR/output"
              grep -F -- '--remove all' "$TMPDIR/output" >/dev/null
              grep -F -- '--add /Applications/Missing Test.app' "$TMPDIR/output" >/dev/null
              bash ${finderActivation} > "$TMPDIR/finder-output"
              grep -F -- 'finder-favorites apply' "$TMPDIR/finder-output" >/dev/null
              test -f ${finderConfiguration}
              test ! -L ${finderConfiguration}
              grep -F -- '--config ${finderConfiguration}' \
                "$TMPDIR/finder-output" >/dev/null
              test ! -e /Users/check-user/.cache/home-manager-macos
              test ! -e /Users/check-user/.local/state/finder-favorites
              touch "$out"
            '';
      };
    };
}
