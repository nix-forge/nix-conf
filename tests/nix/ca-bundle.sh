#!/usr/bin/env bash
set -euo pipefail
BASE_BUNDLE=${BASE_BUNDLE:?Nix must provide the baseline bundle}
FILTERED_BUNDLE=${FILTERED_BUNDLE:?Nix must provide the configured bundle}
out=${out:?Nix must provide the check output}

affected='86:A1:EC:BA:08:9C:4A:8D:3B:BE:27:34:C6:12:BA:34:1D:81:3E:04:3C:F9:E8:A8:62:CD:5C:57:A3:6B:BE:6B'
unaffected='96:BC:EC:06:26:49:76:F3:74:60:77:9A:CF:28:C5:A7:CF:E8:A3:C0:AA:E1:1A:8F:FC:EE:05:C0:BD:DF:08:C6'
unaffected_em_sign=(
  'BC:4D:80:9B:15:18:9D:78:DB:3E:1D:8C:F4:F9:72:6A:79:5D:A1:64:3C:A5:F1:35:8E:1D:DB:0E:DC:0D:7E:B3'
  '12:56:09:AA:30:1D:A0:A2:49:B9:7A:82:39:CB:6A:34:21:6F:44:DC:AC:9F:39:54:B1:42:92:F2:E8:C8:60:8F'
  '40:F6:AF:03:46:A9:9A:A1:CD:1D:55:5A:4E:9C:CE:62:C7:F9:63:46:03:EE:40:66:15:83:3D:C8:C8:D0:03:67'
)

has_fingerprint() {
  local directory=$1 expected=$2 certificate fingerprint
  for certificate in "$directory"/cert-*.pem; do
    fingerprint=$(openssl x509 -in "$certificate" -noout -fingerprint -sha256 | cut -d= -f2)
    if [[ $fingerprint == "$expected" ]]; then
      return 0
    fi
  done
  return 1
}

has_rejected_server_use() {
  local directory=$1 expected=$2 certificate fingerprint
  for certificate in "$directory"/cert-*.pem; do
    fingerprint=$(openssl x509 -in "$certificate" -noout -fingerprint -sha256 | cut -d= -f2)
    if [[ $fingerprint == "$expected" ]]; then
      openssl x509 -in "$certificate" -noout -text |
        grep -A8 '^Rejected Uses:' |
        grep -Fq 'TLS Web Server Authentication'
      return
    fi
  done
  return 1
}

copy_certs() {
  local directory=$1 output=$2 certificate number=0
  mkdir -p "$output"
  for certificate in "$directory"/*.crt; do
    number=$((number + 1))
    cp "$certificate" "$output/cert-$(printf '%04d' "$number").pem"
  done
}

certificate_for_fingerprint() {
  local directory=$1 expected=$2 certificate fingerprint
  for certificate in "$directory"/cert-*.pem; do
    fingerprint=$(openssl x509 -in "$certificate" -noout -fingerprint -sha256 | cut -d= -f2)
    if [[ $fingerprint == "$expected" ]]; then
      printf '%s\n' "$certificate"
      return 0
    fi
  done
  return 1
}

copy_certs "$BASE_UNBUNDLED" "$TMPDIR/base"
if ! has_fingerprint "$TMPDIR/base" "$affected"; then
  echo 'The regression fixture no longer contains its affected baseline root.' >&2
  exit 1
fi

test -s "$FILTERED_BUNDLE"
copy_certs "$FILTERED_UNBUNDLED" "$TMPDIR/filtered"
if ! has_fingerprint "$TMPDIR/filtered" "$affected"; then
  echo 'The filtered CA bundle omitted the affected root instead of recording distrust.' >&2
  exit 1
fi
if ! has_rejected_server_use "$TMPDIR/filtered" "$affected"; then
  echo 'The blacklisted root is not rejected for TLS server use.' >&2
  exit 1
fi

# Verify the trust decision with OpenSSL rather than relying only on the
# p11-kit metadata rendered by the bundle. `-purpose any` is used for
# self-signed trust anchors; the filtered server-purpose check must report
# the explicit certificate-rejected error.
affected_base=$(certificate_for_fingerprint "$TMPDIR/base" "$affected")
openssl x509 -in "$affected_base" -out "$TMPDIR/affected.pem"
affected_base="$TMPDIR/affected.pem"
affected_filtered="$affected_base"
base_bundle="$BASE_BUNDLE"
filtered_bundle="$FILTERED_BUNDLE"
if ! openssl verify -no-CApath -no-CAstore -purpose any -CAfile "$base_bundle" "$affected_base" >/dev/null 2>"$TMPDIR/affected-base-error"; then
  echo 'The baseline affected root is not trusted by OpenSSL.' >&2
  cat "$TMPDIR/affected-base-error" >&2
  exit 1
fi
if openssl verify -no-CApath -no-CAstore -purpose any -CAfile "$filtered_bundle" "$affected_filtered" >"$TMPDIR/affected-filtered-output" 2>&1; then
  echo 'The blacklisted root remains trusted by OpenSSL.' >&2
  exit 1
fi
grep -Fq 'certificate rejected' "$TMPDIR/affected-filtered-output"
if openssl verify -no-CApath -no-CAstore -purpose sslserver -CAfile "$filtered_bundle" "$affected_filtered" >"$TMPDIR/affected-server-output" 2>&1; then
  echo 'The blacklisted root remains usable for TLS server authentication.' >&2
  exit 1
fi
grep -Fq 'certificate rejected' "$TMPDIR/affected-server-output"

if ! has_fingerprint "$TMPDIR/filtered" "$unaffected"; then
  echo 'An unaffected root disappeared from the filtered CA bundle.' >&2
  exit 1
fi
if has_rejected_server_use "$TMPDIR/filtered" "$unaffected"; then
  echo 'An unaffected root was marked as rejected for TLS server use.' >&2
  exit 1
fi
for fingerprint in "${unaffected_em_sign[@]}"; do
  if ! has_fingerprint "$TMPDIR/filtered" "$fingerprint"; then
    echo "An unaffected public root disappeared: $fingerprint" >&2
    exit 1
  fi
  if has_rejected_server_use "$TMPDIR/filtered" "$fingerprint"; then
    echo "An unaffected public root was rejected: $fingerprint" >&2
    exit 1
  fi
  control=$(certificate_for_fingerprint "$TMPDIR/filtered" "$fingerprint")
  openssl x509 -in "$control" -out "$TMPDIR/control.pem"
  if ! openssl verify -no-CApath -no-CAstore -purpose any -CAfile "$filtered_bundle" "$TMPDIR/control.pem" >/dev/null 2>"$TMPDIR/control-error"; then
    echo "An unaffected public root failed OpenSSL trust verification: $fingerprint" >&2
    cat "$TMPDIR/control-error" >&2
    exit 1
  fi
done
awk '
  /^\[p11-kit-object-v1\]$/ { affected = 0 }
  /^label: "emSign ECC Root CA - G3"$/ { affected = 1 }
  affected && /^x-distrusted: true$/ { rejected = 1 }
  END { exit !rejected }
' "$P11_SOURCE/ca-bundle.trust.p11-kit"
touch "$out"
