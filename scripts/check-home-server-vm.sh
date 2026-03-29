#!/usr/bin/env bash
set -euo pipefail

hostname="${HOME_SERVER_VM_HOSTNAME:-home-server-vm}"
run_dir="${HOME_SERVER_VM_RUN_DIR:-${TMPDIR:-/tmp}/${hostname}-run}"
connect_mode="${HOME_SERVER_VM_CONNECT_MODE:-auto}"
guest_ip="${HOME_SERVER_VM_GUEST_IP:-}"
guest_ip_file="${HOME_SERVER_VM_GUEST_IP_FILE:-${run_dir}/guest-ip}"
net_mac="${HOME_SERVER_VM_NET_MAC:-}"
ssh_host="${HOME_SERVER_VM_SSH_HOST:-127.0.0.1}"
ssh_port="${HOME_SERVER_VM_SSH_PORT:-}"
ssh_user="${HOME_SERVER_VM_SSH_USER:-testadmin}"
http_port="${HOME_SERVER_VM_HTTP_PORT:-}"
wait_seconds="${HOME_SERVER_VM_WAIT_SECONDS:-45}"
http_connect_timeout="${HOME_SERVER_VM_HTTP_CONNECT_TIMEOUT:-1}"
http_max_time="${HOME_SERVER_VM_HTTP_MAX_TIME:-3}"
http_retries="${HOME_SERVER_VM_HTTP_RETRIES:-3}"
http_retry_delay="${HOME_SERVER_VM_HTTP_RETRY_DELAY:-2}"
service_retries="${HOME_SERVER_VM_SERVICE_RETRIES:-3}"
service_retry_delay="${HOME_SERVER_VM_SERVICE_RETRY_DELAY:-3}"
core_wait_seconds="${HOME_SERVER_VM_CORE_WAIT_SECONDS:-60}"
ingress_probe_path="${HOME_SERVER_VM_INGRESS_PROBE_PATH:-/healthz}"
homepage_probe_required="${HOME_SERVER_VM_HOMEPAGE_PROBE_REQUIRED:-0}"
profile_mode="${HOME_SERVER_VM_PROFILE:-smoke}"
enable_media_probes="${HOME_SERVER_VM_ENABLE_MEDIA_PROBES:-}"
tcp_probe_count="${HOME_SERVER_VM_TCP_PROBE_COUNT:-12}"
tcp_probe_delay="${HOME_SERVER_VM_TCP_PROBE_DELAY:-1}"
media_allowed_http_codes="${HOME_SERVER_VM_MEDIA_ALLOWED_HTTP_CODES:-200 301 302 303 307 308 401 403}"

normalize_mac() {
  printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]'
}

resolve_guest_ip_from_leases() {
  local target_mac target_name ip_prefix
  target_mac="$(normalize_mac "$1")"
  target_name="$2"
  ip_prefix="${3:-}"
  python3 - "$target_mac" "$target_name" "$ip_prefix" << 'PY'
import re
import sys

target_mac = sys.argv[1].lower()
target_name = sys.argv[2]
ip_prefix = sys.argv[3]
path = "/var/db/dhcpd_leases"

try:
    data = open(path, "r", encoding="utf-8", errors="ignore").read()
except OSError:
    sys.exit(1)

mac_candidate = None

for block in data.split("\n{\n"):
    name_match = re.search(r"name=([^\n]+)", block)
    mac_match = re.search(r"hw_address=1,([^\n]+)", block)
    ip_match = re.search(r"ip_address=([^\n]+)", block)
    lease_match = re.search(r"lease=([^\n]+)", block)
    if not ip_match:
        continue

    ip = ip_match.group(1).strip()
    if ip_prefix and not ip.startswith(f"{ip_prefix}."):
        continue

    lease_value = -1
    if lease_match:
        raw_lease = lease_match.group(1).strip()
        try:
            lease_value = int(raw_lease, 16) if raw_lease.startswith("0x") else int(raw_lease)
        except ValueError:
            lease_value = -1

    if target_name and name_match and name_match.group(1).strip() == target_name:
        if not mac_candidate or lease_value > mac_candidate[0]:
            mac_candidate = (lease_value, ip)
        continue

    if not mac_match:
        continue

    parts = mac_match.group(1).strip().split(":")
    try:
        normalized = ":".join(f"{int(part, 16):02x}" for part in parts)
    except ValueError:
        continue

    if normalized == target_mac:
        if not mac_candidate or lease_value > mac_candidate[0]:
            mac_candidate = (lease_value, ip)

if mac_candidate:
    print(mac_candidate[1])
    sys.exit(0)

sys.exit(1)
PY
}

resolve_guest_ip_prefix_hint() {
  local mode_file vmnet_info legacy_vmnet_info mode info_source
  mode_file="${run_dir}/runner-mode"
  vmnet_info="${run_dir}/vmnet.json"
  legacy_vmnet_info="${run_dir}/vmnet-helper.json"

  if [[ -f ${mode_file} ]]; then
    mode="$(head -n 1 "${mode_file}" | tr -d '[:space:]')"
    if [[ ${mode} == vfkit-vmnet-shared* || ${mode} == vfkit-vmnet-host* ]]; then
      if [[ -f ${vmnet_info} ]]; then
        info_source="${vmnet_info}"
      elif [[ -f ${legacy_vmnet_info} ]]; then
        info_source="${legacy_vmnet_info}"
      fi

      if [[ -n ${info_source:-} ]]; then
        python3 - "${info_source}" << 'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)

for key in ("vmnet_start_address", "start_address"):
    start = (data.get(key) or "").strip()
    parts = start.split(".")
    if len(parts) == 4:
        print(".".join(parts[:3]))
        break
PY
      fi
    fi
  fi
}

if [[ ${connect_mode} == "guest-ip" ]]; then
  guest_ip_prefix="${HOME_SERVER_VM_GUEST_IP_PREFIX:-}"
  if [[ -z ${guest_ip_prefix} ]]; then
    guest_ip_prefix="$(resolve_guest_ip_prefix_hint || true)"
  fi

  if [[ -z ${guest_ip} ]]; then
    guest_ip="$(resolve_guest_ip_from_leases "${net_mac}" "${hostname}" "${guest_ip_prefix}" || true)"
  fi

  if [[ -z ${guest_ip} && -f ${guest_ip_file} ]]; then
    guest_ip="$(head -n 1 "${guest_ip_file}" | tr -d '[:space:]')"
  fi

  if [[ -z ${guest_ip} ]]; then
    echo "ERROR: HOME_SERVER_VM_CONNECT_MODE=guest-ip but no guest IP was available." >&2
    echo "Hint: set HOME_SERVER_VM_GUEST_IP, or provide HOME_SERVER_VM_NET_MAC, or ensure ${guest_ip_file} exists." >&2
    exit 1
  fi

  ssh_host="${guest_ip}"
  if [[ -z ${ssh_port} ]]; then
    ssh_port="22"
  fi
  if [[ -z ${http_port} ]]; then
    http_port="8080"
  fi
else
  if [[ -z ${ssh_port} ]]; then
    ssh_port="2222"
  fi
  if [[ -z ${http_port} ]]; then
    http_port="8080"
  fi
fi
ssh_opts=(
  -p "$ssh_port"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=5
)

if [[ -n ${HOME_SERVER_VM_SSH_IDENTITY:-} ]]; then
  ssh_opts+=(-i "$HOME_SERVER_VM_SSH_IDENTITY")
elif [[ -f ${HOME:-}/.ssh/id_ed25519 ]]; then
  ssh_opts+=(-i "${HOME}/.ssh/id_ed25519")
fi

base_url="http://${ssh_host}:${http_port}"
core_paths=(
  /healthz
  /
)

media_paths=(
  /jellyfin/
  /jellyseerr/
  /sonarr/
  /radarr/
  /lidarr/
  /readarr/
  /bazarr/
  /prowlarr/
  /qbittorrent/
  /nzbget/
  /vaultwarden/
)

if [[ -z ${enable_media_probes} ]]; then
  if [[ ${profile_mode} == "parity" ]]; then
    enable_media_probes="1"
  else
    enable_media_probes="0"
  fi
fi

core_failed_urls=()
media_failed_urls=()

remote_network_checks=$(
  cat << 'EOF'
set -euo pipefail
echo "guest: $(hostname)"
echo "listeners:"
ss -ltn | grep -E "(:22 |:5055 |:6767 |:6789 |:7878 |:8080 |:8081 |:8096 |:8222 |:8686 |:8787 |:8989 |:9696 )|Local Address:Port" || true
echo
echo "policy routing:"
ip rule
echo
echo "table 51820:"
ip route show table 51820 || true
echo
echo "resolver status:"
resolvectl status || true
echo
echo "failed units:"
systemctl --failed --no-pager || true
EOF
)

remote_services=(
  sshd
  nginx
)

if [[ ${profile_mode} == "parity" || ${enable_media_probes} == "1" ]]; then
  remote_services+=(
    jellyfin
    jellyseerr
    sonarr
    radarr
    lidarr
    readarr
    bazarr
    prowlarr
    qbittorrent
    nzbget
    vaultwarden
  )
fi

remote_service_entries=""
for service in "${remote_services[@]}"; do
  remote_service_entries+="  ${service}"$'\n'
done

remote_service_status_checks="set -euo pipefail
services=(
${remote_service_entries})
for service in \"\${services[@]}\"; do
  if systemctl is-active --quiet \"\${service}.service\"; then
    printf 'OK   %s\\n' \"\${service}.service\"
  else
    printf 'FAIL %s\\n' \"\${service}.service\" >&2
    systemctl --no-pager --full status \"\${service}.service\" || true
    exit 1
  fi
done"

remote_service_ip_checks=$(
  cat << 'EOF'
set -euo pipefail
for user in qbittorrent nzbget prowlarr; do
  printf "%s public-ip: " "$user"
  sudo -n -u "$user" curl -4 -fsS --max-time 10 https://ifconfig.me
  printf "\n"
done
EOF
)

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

error() {
  printf 'ERROR: %s\n' "$*" >&2
}

wait_for_port() {
  local host="$1"
  local port="$2"
  local deadline=$((SECONDS + wait_seconds))

  while ((SECONDS < deadline)); do
    if nc -z -w 1 "$host" "$port" > /dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

check_url() {
  local url="$1"
  local allowed_codes="${2:-200 301 302 303 307 308}"
  local status
  local attempt

  for ((attempt = 1; attempt <= http_retries; attempt += 1)); do
    status="$({
      curl -sS -o /dev/null \
        --connect-timeout "$http_connect_timeout" \
        --max-time "$http_max_time" \
        -w '%{http_code}' \
        "$url"
    } || true)"

    if [[ " ${allowed_codes} " == *" ${status} "* ]]; then
      printf 'OK   %s -> %s\n' "$url" "$status"
      return 0
    fi

    if ((attempt < http_retries)); then
      sleep "$http_retry_delay"
    fi
  done

  printf 'FAIL %s -> %s (after %s attempts)\n' "$url" "${status:-curl-error}" "$http_retries" >&2
  return 1
}

wait_for_url() {
  local url="$1"
  local deadline=$((SECONDS + core_wait_seconds))

  while ((SECONDS < deadline)); do
    if check_url "$url" > /dev/null 2>&1; then
      printf 'OK   %s became ready\n' "$url"
      return 0
    fi
    sleep 1
  done

  printf 'FAIL %s did not become ready within %ss\n' "$url" "$core_wait_seconds" >&2
  return 1
}

ssh_batch() {
  ssh "${ssh_opts[@]}" -o BatchMode=yes "${ssh_user}@${ssh_host}" "$@"
}

collect_timeout_debug() {
  warn "Collecting timeout diagnostics"
  warn "Host listener snapshot"
  lsof -nP -iTCP:"${ssh_port}" -sTCP:LISTEN || true
  lsof -nP -iTCP:"${http_port}" -sTCP:LISTEN || true

  warn "Host TCP probe (${tcp_probe_count} samples, ${tcp_probe_delay}s delay)"
  for ((sample = 1; sample <= tcp_probe_count; sample += 1)); do
    ssh_state="closed"
    http_state="closed"
    if nc -z -w 1 "${ssh_host}" "${ssh_port}" > /dev/null 2>&1; then
      ssh_state="open"
    fi
    if nc -z -w 1 "${ssh_host}" "${http_port}" > /dev/null 2>&1; then
      http_state="open"
    fi
    printf 'sample %02d: ssh=%s http=%s\n' "${sample}" "${ssh_state}" "${http_state}"
    sleep "${tcp_probe_delay}"
  done

  if ssh_batch true > /dev/null 2>&1; then
    ssh_batch 'set +e; echo "service states:"; systemctl is-active nginx homepage-dashboard sshd jellyfin jellyseerr sonarr radarr lidarr readarr bazarr prowlarr qbittorrent nzbget vaultwarden; echo; echo "listener snapshot:"; ss -ltn | grep -E ":(22|5055|6767|6789|7878|8080|8081|8082|8096|8222|8686|8787|8989|9696)" || true; echo; echo "guest curl 8082:"; curl -sS -o /dev/null -w "%{http_code}\n" --connect-timeout 2 --max-time 4 http://127.0.0.1:8082/ || true; echo "guest curl 8080 healthz:"; curl -sS -o /dev/null -w "%{http_code}\n" --connect-timeout 2 --max-time 4 http://127.0.0.1:8080/healthz || true; echo "guest curl 8080 root:"; curl -sS -o /dev/null -w "%{http_code}\n" --connect-timeout 2 --max-time 4 http://127.0.0.1:8080/ || true; echo; echo "kernel net watchdog snapshot:"; journalctl -k -n 120 --no-pager | grep -E "NETDEV WATCHDOG|virtio_net|hung task" || true' || true
  else
    warn "Batch SSH unavailable; cannot collect guest-side timeout diagnostics"
  fi
}

log "Waiting for SSH on ${ssh_host}:${ssh_port}"
log "Check profile mode: ${profile_mode} (media probes: ${enable_media_probes})"
log "Connect mode: ${connect_mode} (ssh_host=${ssh_host}, ssh_port=${ssh_port}, http_port=${http_port})"
if ! wait_for_port "$ssh_host" "$ssh_port"; then
  warn "Timed out waiting for SSH on ${ssh_host}:${ssh_port}."
  if [[ ${connect_mode} == "guest-ip" ]]; then
    warn "Start the VM in another terminal with: just home-server-vm-run-macos-vfkit"
  else
    warn "Start the VM in another terminal with: just home-server-vm-run-macos"
  fi
  exit 1
fi

log "Waiting for ingress readiness endpoint (${ingress_probe_path})"
if ! wait_for_url "${base_url}${ingress_probe_path}"; then
  error "HTTP ingress readiness probe failed"
  collect_timeout_debug
  exit 1
fi

log "Checking core HTTP endpoints"
for path in "${core_paths[@]}"; do
  if [[ ${path} == "/" ]]; then
    if ! check_url "${base_url}${path}"; then
      if [[ ${homepage_probe_required} == "1" ]]; then
        error "Homepage probe failed and is required"
        collect_timeout_debug
        exit 1
      fi

      warn "Homepage probe failed, but ingress is healthy. Continuing with media and guest checks."
    fi
    continue
  fi

  if ! check_url "${base_url}${path}"; then
    core_failed_urls+=("${base_url}${path}")
  fi
done

if [[ ${enable_media_probes} == "1" ]]; then
  log "Checking media HTTP endpoints"
  for path in "${media_paths[@]}"; do
    if ! check_url "${base_url}${path}" "${media_allowed_http_codes}"; then
      media_failed_urls+=("${base_url}${path}")
    fi
  done
else
  log "Skipping media HTTP endpoints for profile (${profile_mode})"
fi

log "Checking whether batch SSH access is available"
if ssh_batch true > /dev/null 2>&1; then
  log "Checking guest service health"
  service_ok=0
  for ((attempt = 1; attempt <= service_retries; attempt += 1)); do
    if ssh_batch "$remote_service_status_checks"; then
      service_ok=1
      break
    fi

    warn "Guest service health attempt ${attempt}/${service_retries} failed"
    if ((attempt < service_retries)); then
      sleep "$service_retry_delay"
    fi
  done

  if ((service_ok == 0)); then
    error "Guest service health checks failed"
    exit 1
  fi

  log "Running guest-side network checks over SSH"
  ssh_batch "$remote_network_checks"

  if [[ ${enable_media_probes} == "1" ]] && ssh_batch 'sudo -n true' > /dev/null 2>&1; then
    log "Running service-user egress checks"
    ssh_batch "$remote_service_ip_checks"
  elif [[ ${enable_media_probes} != "1" ]]; then
    log "Skipping service-user egress checks for profile (${profile_mode})"
  else
    warn "Passwordless sudo is unavailable over SSH; run the service-user egress checks manually after logging in."
  fi
else
  warn "Batch SSH access is unavailable."
  warn "Add HOME_SERVER_VM_SSH_IDENTITY or use the authorized key configured for testadmin to enable guest assertions."
fi

if [[ ${enable_media_probes} == "1" ]] && ((${#media_failed_urls[@]} > 0)); then
  log "Retrying failed media endpoints after guest service checks"
  remaining_media_failed=()
  for url in "${media_failed_urls[@]}"; do
    if ! check_url "${url}" "${media_allowed_http_codes}"; then
      remaining_media_failed+=("${url}")
    fi
  done
  media_failed_urls=("${remaining_media_failed[@]}")
fi

failed_urls=("${core_failed_urls[@]}" "${media_failed_urls[@]}")

if ((${#failed_urls[@]} > 0)); then
  error "HTTP probes failed for ${#failed_urls[@]} endpoint(s):"
  printf ' - %s\n' "${failed_urls[@]}" >&2
  collect_timeout_debug
  exit 1
fi

log "Checks finished"
