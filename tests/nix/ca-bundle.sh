#!/usr/bin/env bash
set -euo pipefail
BASE_BUNDLE=${BASE_BUNDLE:?Nix must provide the baseline bundle}
FILTERED_BUNDLE=${FILTERED_BUNDLE:?Nix must provide the configured bundle}
out=${out:?Nix must provide the check output}

affected='86:A1:EC:BA:08:9C:4A:8D:3B:BE:27:34:C6:12:BA:34:1D:81:3E:04:3C:F9:E8:A8:62:CD:5C:57:A3:6B:BE:6B'
removed=(
  "$affected"
  'BC:4D:80:9B:15:18:9D:78:DB:3E:1D:8C:F4:F9:72:6A:79:5D:A1:64:3C:A5:F1:35:8E:1D:DB:0E:DC:0D:7E:B3'
  '12:56:09:AA:30:1D:A0:A2:49:B9:7A:82:39:CB:6A:34:21:6F:44:DC:AC:9F:39:54:B1:42:92:F2:E8:C8:60:8F'
)
controls=(
  '96:BC:EC:06:26:49:76:F3:74:60:77:9A:CF:28:C5:A7:CF:E8:A3:C0:AA:E1:1A:8F:FC:EE:05:C0:BD:DF:08:C6'
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
test -s "$FILTERED_BUNDLE"
# Inspect the actual configured bundle, including NixOS's own exclusions.
# Preserve TRUSTED CERTIFICATE blocks and their OpenSSL trust metadata.
mkdir "$TMPDIR/filtered"
awk -v directory="$TMPDIR/filtered" '
  /^-----BEGIN (TRUSTED )?CERTIFICATE-----$/ {
    number++
    path = sprintf("%s/cert-%04d.pem", directory, number)
    inside = 1
  }
  inside { print > path }
  /^-----END (TRUSTED )?CERTIFICATE-----$/ { close(path); inside = 0 }
  END { if (number == 0 || inside) exit 1 }
' "$FILTERED_BUNDLE"
for fingerprint in "${removed[@]}"; do
  for directory in "$TMPDIR/base" "$TMPDIR/filtered"; do
    if has_fingerprint "$directory" "$fingerprint"; then
      echo "An upstream-removed root returned to the CA store: $fingerprint" >&2
      exit 1
    fi
  done
done

# NSS 3.131.1 omits G3 entirely. Keep its historical public certificate only
# as a negative fixture, with a positive control proving it is parseable and
# valid when explicitly trusted in this single isolated invocation.
fingerprint=$(openssl x509 -in "$AFFECTED_CERTIFICATE" -noout -fingerprint -sha256 | cut -d= -f2)
test "$fingerprint" = "$affected"
openssl verify -no-CApath -no-CAstore -purpose any -CAfile "$AFFECTED_CERTIFICATE" "$AFFECTED_CERTIFICATE"
for purpose in any sslserver; do
  if openssl verify -no-CApath -no-CAstore -purpose "$purpose" -CAfile "$FILTERED_BUNDLE" "$AFFECTED_CERTIFICATE" >"$TMPDIR/affected-output" 2>&1; then
    echo "The removed G3 root remains trusted for $purpose." >&2
    exit 1
  fi
  grep -Eq 'self-signed certificate|unable to get local issuer certificate|certificate rejected' "$TMPDIR/affected-output"
done

# ISRG X1 and emSign G1 remain public roots in this NSS release. C1 and C3
# are deliberately not positive controls: upstream removed those as well.
for fingerprint in "${controls[@]}"; do
  for directory in "$TMPDIR/base" "$TMPDIR/filtered"; do
    if ! has_fingerprint "$directory" "$fingerprint"; then
      echo "An unaffected public root disappeared: $fingerprint" >&2
      exit 1
    fi
  done
  if has_rejected_server_use "$TMPDIR/filtered" "$fingerprint"; then
    echo "An unaffected public root was rejected: $fingerprint" >&2
    exit 1
  fi
  control=$(certificate_for_fingerprint "$TMPDIR/filtered" "$fingerprint")
  openssl x509 -in "$control" -out "$TMPDIR/control.pem"
  for bundle in "$BASE_BUNDLE" "$FILTERED_BUNDLE"; do
    for purpose in any sslserver; do
      if ! openssl verify -no-CApath -no-CAstore -purpose "$purpose" -CAfile "$bundle" "$TMPDIR/control.pem" >/dev/null 2>"$TMPDIR/control-error"; then
        echo "An unaffected public root failed OpenSSL $purpose trust verification: $fingerprint" >&2
        cat "$TMPDIR/control-error" >&2
        exit 1
      fi
    done
  done
done
test -s "$P11_SOURCE/ca-bundle.trust.p11-kit"
if grep -Eq '^label: "emSign (ECC Root CA - G3|ECC Root CA - C3|Root CA - C1)"$' "$P11_SOURCE/ca-bundle.trust.p11-kit"; then
  echo 'An upstream-removed emSign root returned to the p11-kit trust source.' >&2
  exit 1
fi
grep -Fq 'label: "ISRG Root X1"' "$P11_SOURCE/ca-bundle.trust.p11-kit"
grep -Fq 'label: "emSign Root CA - G1"' "$P11_SOURCE/ca-bundle.trust.p11-kit"
touch "$out"
