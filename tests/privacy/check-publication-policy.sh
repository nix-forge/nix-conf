#!/usr/bin/env bash
set -euo pipefail

policy=$(realpath "$1")
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
