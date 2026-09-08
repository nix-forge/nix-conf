#!/usr/bin/env bash
set -euo pipefail

policy=$(realpath "$1")
scan_script=$(realpath "$2")
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/docs" "$fixture/hosts"

expect_detection() {
  local filename=$1 value=$2 rule=$3 status=0
  mkdir -p "$fixture/$(dirname "$filename")"
  printf '%s\n' "$value" >"$fixture/$filename"
  (
    cd "$fixture"
    gitleaks dir . --config "$policy" --redact --no-banner \
      --report-format json --report-path "$fixture/report.json"
  ) >"$fixture/scan.log" 2>&1 || status=$?
  if [[ $status != 1 ]] || ! grep -Fq "\"RuleID\": \"$rule\"" "$fixture/report.json"; then
    printf 'Expected %s in %s; scanner exited %s\n' "$rule" "$filename" "$status" >&2
    cat "$fixture/scan.log" >&2
    exit 1
  fi
  rm "$fixture/$filename" "$fixture/report.json" "$fixture/scan.log"
}

# Construct fictional canaries so the policy can also scan this source file.
expect_detection docs/note.md "Source: /home/""publication-canary-operator/notes" docs-personal-home-path
expect_detection docs/note.md "Source: /Users/""publication-canary-operator/notes" docs-personal-home-path
expect_detection docs/note.md "publication.canary.person@""gmail.com" docs-personal-email
expect_detection docs/note.md "AA:BB:CC:""DD:EE:FF" docs-hardware-address
expect_detection hosts/layout.nix "/dev/disk/by-id/""nvme-EXAMPLE_SERIAL" hardware-disk-identity

# Exceptions for public verification material and booleans must not hide keys.
canary=aB3dE6gH9jK2mN5pQ8sT1vW4yZ7bC0eF3hI6
expect_detection scripts/secret""ctl.py "secret_""id, allow_derived=True; password=\"$canary\"" generic-api-key
for path in nixosModules/networking/dnscrypt-proxy.nix \
  _nixOSModules/networking/dnscrypt-proxy.nix \
  _nixOSModules/hardware/networking/dnscrypt-proxy.nix; do
  expect_detection "$path" "minisign_key = \"$canary\"" generic-api-key
done

cat >"$fixture/docs/note.md" <<'EOF'
$HOME/Developer/project
<USER>@<HOSTNAME>
developer@example.org
123+example@users.noreply.github.com
/Users/example/Developer
[source](../modules/home/desktop/default.nix)
/dev/disk/by-id/REPLACE-WITH-VERIFIED-SYSTEM-DISK
EOF
(
  cd "$fixture"
  gitleaks dir . --config "$policy" --redact --no-banner
)
printf 'Publication policy checks passed.\n'

# Real Git history verifies immutable metadata exceptions preserve credentials.
repository="$fixture/repository"
mkdir -p "$repository/docs"
cp "$policy" "$repository/.gitleaks.toml"
(
  cd "$repository"
  git init -q
  git config user.name "Publication policy test"
  git config user.email "test@example.org"
  printf 'Source: /home/%s/notes\n' publication-canary-operator >docs/note.md
  git add .
  git commit -qm 'Historical metadata'
  historical_metadata=$(git rev-parse HEAD)
  printf 'Portable documentation\n' >docs/note.md
  git add .
  git commit -qm 'Remove historical metadata'
  if bash "$scan_script" >"$fixture/unreviewed-scan.log" 2>&1; then
    echo 'Unreviewed historical metadata escaped the scan' >&2
    exit 1
  fi

  allow_metadata_commit() {
    printf '\n[[allowlists]]\ntargetRules = ["docs-personal-home-path"]\ncommits = ["%s"]\n' "$1" >>.gitleaks.toml
    git add .gitleaks.toml
    git commit -qm 'Review immutable historical metadata'
  }
  allow_metadata_commit "$historical_metadata"
  bash "$scan_script"

  printf 'Source: /home/%s/notes\n' publication-canary-operator >docs/note.md
  git add .
  git commit -qm 'Current metadata must fail'
  # Exempt this historical commit so only the full current-tree scan detects it.
  allow_metadata_commit "$(git rev-parse HEAD)"
  if bash "$scan_script" >"$fixture/current-scan.log" 2>&1; then
    echo 'Unchanged current metadata escaped the committed-tree scan' >&2
    exit 1
  fi
  printf 'Portable documentation\n' >docs/note.md
  printf 'password="%s"\n' "$canary" >credential.txt
  git add .
  git commit -qm 'Historical credential canary'
  historical_credential=$(git rev-parse HEAD)
  git rm -q credential.txt
  git commit -qm 'Remove credential canary'
  allow_metadata_commit "$historical_credential"
  if bash "$scan_script" >"$fixture/history-scan.log" 2>&1; then
    echo 'Metadata exception hid a removed credential' >&2
    exit 1
  fi
)
printf 'Publication history and committed-tree checks passed.\n'
