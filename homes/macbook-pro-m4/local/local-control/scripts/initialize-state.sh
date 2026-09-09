# shellcheck shell=sh
set -eu
umask 0077

private_path_guard=@privatePathGuard@
secure_files=@secureFileSystem@
state_dir=${LOCAL_CONTROL_STATE_DIR:?}
dashboard_dir=${LOCAL_CONTROL_DASHBOARD_DIR:?}
database_dir=${LOCAL_CONTROL_DATABASE_DIR:?}
database_socket_dir=${LOCAL_CONTROL_DATABASE_SOCKET_DIR:?}
pki_dir=${LOCAL_CONTROL_PKI_DIR:?}
log_dir=${LOCAL_CONTROL_LOG_DIR:?}
environment_file=${LOCAL_CONTROL_ENVIRONMENT_FILE:?}
initdb=@initdb@
openssl=@openssl@
server_extensions=@serverCertificateExtensions@
client_extensions=@clientCertificateExtensions@

"$private_path_guard" ensure-directory "$state_dir" 'Local control-plane state directory'
if [ ! -e "$dashboard_dir" ] && [ ! -L "$dashboard_dir" ]; then
  ln -s current/dashboard "$dashboard_dir"
elif [ ! -L "$dashboard_dir" ]; then
  printf 'Dashboard deployment pointer must be a symbolic link.\n' >&2
  exit 1
fi
"$private_path_guard" ensure-directory "$database_dir" 'Local database directory'

database_state="$("$secure_files" cluster-state "$database_dir" 18)" || {
  printf 'Refusing an incomplete, unsafe, or incompatible database directory.\n' >&2
  exit 1
}
if [ "$database_state" = missing ]; then
  if ! "$secure_files" initialize-cluster "$database_dir" 18 "$initdb" \
    --pgdata=. --auth-local=trust --auth-host=scram-sha-256 --encoding=UTF8 --no-locale; then
    printf 'Refusing to initialize an unsafe database directory.\n' >&2
    exit 1
  fi
fi

environment_file_state="$("$secure_files" inspect-generation-file "$environment_file" 600)" || {
  printf 'Production environment must be a safe owner-only regular file.\n' >&2
  exit 1
}
if [ "$environment_file_state" = missing ]; then
  printf 'Production environment is not configured; application and proxy remain stopped.\n' >&2
fi

"$private_path_guard" ensure-directory "$database_socket_dir" 'Local database socket directory'
"$private_path_guard" ensure-directory "$pki_dir" 'Local service PKI directory'
"$private_path_guard" ensure-directory "$log_dir" 'Local service log directory'

check_optional_generated_file() {
  if ! "$secure_files" inspect-file "$1" "$2" >/dev/null; then
    printf 'Generated path is missing, unsafe, or has the wrong mode: %s\n' "$1" >&2
    exit 1
  fi
}

repair_log_file_mode() {
  if ! "$secure_files" repair-file-mode "$1" 600 >/dev/null; then
    printf 'Service log is unsafe or could not be made private: %s\n' "$1" >&2
    exit 1
  fi
}

for file_and_mode in \
  "$pki_dir/ca.key:600" \
  "$pki_dir/ca.crt:644" \
  "$pki_dir/ca.srl:600" \
  "$pki_dir/server.key:600" \
  "$pki_dir/server.crt:644" \
  "$pki_dir/server.csr:600" \
  "$pki_dir/client.key:600" \
  "$pki_dir/client.crt:644" \
  "$pki_dir/client.csr:600" \
  "$pki_dir/client.pfx:600"; do
  check_optional_generated_file "${file_and_mode%:*}" "${file_and_mode##*:}"
done

for log_file in \
  "$log_dir/database.out.log" \
  "$log_dir/database.err.log" \
  "$log_dir/proxy.out.log" \
  "$log_dir/proxy.err.log" \
  "$log_dir/control-api.log" \
  "$log_dir/control-api.error.log" \
  "$log_dir/calculation-worker.log" \
  "$log_dir/calculation-worker.error.log"; do
  repair_log_file_mode "$log_file"
done

ca_certificate_state="$("$secure_files" inspect-file "$pki_dir/ca.crt" 644)" || exit 1
ca_key_state="$("$secure_files" inspect-file "$pki_dir/ca.key" 600)" || exit 1
if [ "$ca_certificate_state" = missing ] && [ "$ca_key_state" = missing ]; then
  "$secure_files" exec-files "$pki_dir" "$openssl" \
    --create ca.key 600 --create ca.crt 644 -- \
    req -x509 -new -nodes -sha256 -days 3650 -newkey rsa:3072 \
    -keyout @ca.key@ -out @ca.crt@ -subj '/CN=Local Service CA' \
    -addext 'basicConstraints=critical,CA:TRUE' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign'
elif [ "$ca_certificate_state" = missing ] || [ "$ca_key_state" = missing ]; then
  printf 'The local service CA is incomplete.\n' >&2
  exit 1
fi

ca_serial_state="$("$secure_files" inspect-file "$pki_dir/ca.srl" 600)" || exit 1
if [ "$ca_serial_state" = missing ]; then
  printf '01\n' | "$secure_files" create-file "$pki_dir/ca.srl" 600
fi

server_certificate_state="$("$secure_files" inspect-file "$pki_dir/server.crt" 644)" || exit 1
server_key_state="$("$secure_files" inspect-file "$pki_dir/server.key" 600)" || exit 1
if [ "$server_certificate_state" = missing ] && [ "$server_key_state" = missing ]; then
  "$secure_files" exec-files "$pki_dir" "$openssl" \
    --create server.key 600 --create server.csr 600 -- \
    req -new -nodes -newkey rsa:3072 -keyout @server.key@ -out @server.csr@ \
    -subj '/CN=local-service'
  "$secure_files" exec-files "$pki_dir" "$openssl" \
    --read ca.crt 644 --read ca.key 600 --update ca.srl 600 --read server.csr 600 \
    --create server.crt 644 -- \
    x509 -req -sha256 -days 825 -in @server.csr@ -CA @ca.crt@ -CAkey @ca.key@ \
    -CAserial @ca.srl@ -out @server.crt@ -extfile "$server_extensions"
elif [ "$server_certificate_state" = missing ] || [ "$server_key_state" = missing ]; then
  printf 'The local service server identity is incomplete.\n' >&2
  exit 1
fi

client_bundle_state="$("$secure_files" inspect-file "$pki_dir/client.pfx" 600)" || exit 1
client_key_state="$("$secure_files" inspect-file "$pki_dir/client.key" 600)" || exit 1
client_certificate_state="$("$secure_files" inspect-file "$pki_dir/client.crt" 644)" || exit 1
if [ "$client_bundle_state" = missing ] &&
  [ "$client_key_state" = missing ] &&
  [ "$client_certificate_state" = missing ]; then
  "$secure_files" exec-files "$pki_dir" "$openssl" \
    --create client.key 600 --create client.csr 600 -- \
    req -new -nodes -newkey rsa:3072 -keyout @client.key@ -out @client.csr@ \
    -subj '/CN=local-client'
  "$secure_files" exec-files "$pki_dir" "$openssl" \
    --read ca.crt 644 --read ca.key 600 --update ca.srl 600 --read client.csr 600 \
    --create client.crt 644 -- \
    x509 -req -sha256 -days 825 -in @client.csr@ -CA @ca.crt@ -CAkey @ca.key@ \
    -CAserial @ca.srl@ -out @client.crt@ -extfile "$client_extensions"
  "$secure_files" exec-files "$pki_dir" "$openssl" \
    --read ca.crt 644 --read client.key 600 --read client.crt 644 --create client.pfx 600 -- \
    pkcs12 -export -out @client.pfx@ -inkey @client.key@ -in @client.crt@ \
    -certfile @ca.crt@ -passout pass:
elif [ "$client_bundle_state" = missing ] ||
  [ "$client_key_state" = missing ] ||
  [ "$client_certificate_state" = missing ]; then
  printf 'The local service client identity is incomplete.\n' >&2
  exit 1
fi
