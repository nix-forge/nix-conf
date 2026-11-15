# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
set -euo pipefail
bash @tests_privacy_check_publication_policy_sh@ @gitleaks_toml@ \
  @github_scripts_scan_publication_sh@
fixture="$TMPDIR/fixture"
mkdir -p "$fixture"
scan_fixture() {
  # Match the repository-relative paths produced by Git scans.
  (
    cd "$fixture"
    gitleaks dir . "$@"
  )
}
for policy in @gitleaks_toml@ @pkgs_gitleaks_toml@ @nix_seal_gitleaks_toml@ \
  @nix_homelab_gitleaks_toml@ @nix_config_framework_gitleaks_toml@; do
  for filename in ordinary.txt .nix-seal/public.nix nix-seal.lock.json \
    pkgs/by-name/sp/spotify-spotx/source.nix crates/nix-seal-cli/src/main.rs \
    tests/nixos/scripts/miniflux_test.py; do
    mkdir -p "$fixture/$(dirname "$filename")"
    # Exercise a provider token and the generic rule used by the
    # public-hash exceptions. Neither fixture is an operational key.
    for prefix in ghp_ ""; do
      printf 'password = "%s%s"\n' "$prefix" 'aB3dE6gH9jK2mN5pQ8sT1vW4yZ7bC0eF3hI6' >"$fixture/$filename"
      status=0
      scan_fixture --config "$policy" --redact --no-banner >"$TMPDIR/scan.log" 2>&1 || status=$?
      if [ "$status" -ne 1 ]; then
        printf 'Expected credential detection for %s under %s, got exit %s\n' "$filename" "$policy" "$status" >&2
        cat "$TMPDIR/scan.log" >&2
        exit 1
      fi
    done
    rm "$fixture/$filename"
  done
done

# The extracted Miniflux fixture reads its password at runtime. Its exact
# source-shaped exception must not hide another credential in that same file.
filename="$fixture/tests/nixos/scripts/miniflux_test.py"
printf '%s%s\n' \
  'command = "curl --fail --silent -u ' 'admin:" + auth' \
  'user = json.loads(machine.succeed(command + "' ' http://127.0.0.1:18080/v1/me"))' >"$filename"
scan_fixture --config @nix_homelab_gitleaks_toml@ --redact --no-banner
gitleaks dir "$fixture" --config @nix_homelab_gitleaks_toml@ --redact --no-banner
printf 'password="%s"\n' 'aB3dE6gH9jK2mN5pQ8sT1vW4yZ7bC0eF3hI6' >>"$filename"
status=0
scan_fixture --config @nix_homelab_gitleaks_toml@ --redact --no-banner \
  >"$TMPDIR/scan.log" 2>&1 || status=$?
if [ "$status" -ne 1 ]; then
  echo "A runtime fixture exception hid another credential" >&2
  cat "$TMPDIR/scan.log" >&2
  exit 1
fi
rm "$filename"

# The public download exception covers only the complete URL
# assignment. Another JWT on that line must remain detectable.
jwt_header=$(printf '{"alg":"HS256","typ":"JWT"}' | base64 | tr -d '=\n')
jwt_payload=$(printf '{"sub":"checker-policy-canary"}' | base64 | tr -d '=\n')
jwt_signature=aB3dE6gH9jK2mN5pQ8sT1vW4yZ7bC0eF3hI6
jwt="$jwt_header.$jwt_payload.$jwt_signature$jwt_signature"
for policy in @gitleaks_toml@ @pkgs_gitleaks_toml@; do
  filename="$fixture/pkgs/by-name/sp/spotify-spotx/source.nix"
  printf 'url = "https://upgrade.scdn.co/upgrade/client/osx-arm64/spotify-autoupdate-1.2.3.tbz?fauth=%s";\n' "$jwt" >"$filename"
  scan_fixture --config "$policy" --redact --no-banner
  sed -i "s/;$/; token=\"$jwt\"/" "$filename"
  status=0
  scan_fixture --config "$policy" --redact --no-banner >"$TMPDIR/scan.log" 2>&1 || status=$?
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
printf 'password=%s\n' "$allowed_canary" >"$fixture/crates/nix-seal-cli/src/main.rs"
scan_fixture --config @nix_seal_gitleaks_toml@ --redact --no-banner
printf 'password=%s; password="%s"\n' "$allowed_canary" \
  'aB3dE6gH9jK2mN5pQ8sT1vW4yZ7bC0eF3hI6' >"$fixture/crates/nix-seal-cli/src/main.rs"
status=0
scan_fixture --config @nix_seal_gitleaks_toml@ \
  --redact --no-banner >"$TMPDIR/scan.log" 2>&1 || status=$?
if [ "$status" -ne 1 ]; then
  echo "A test-value exception hid another credential on the same line" >&2
  cat "$TMPDIR/scan.log" >&2
  exit 1
fi
touch "$out"
