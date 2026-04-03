#!/usr/bin/env bash
set -euo pipefail

flake_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
flake_ref="path:${flake_dir}"

hostname="${HOME_SERVER_VM_HOSTNAME:-home-server-vm}"
disk_image="${HOME_SERVER_VM_DISK_IMAGE:-${flake_dir}/${hostname}.qcow2}"
run_dir="${HOME_SERVER_VM_RUN_DIR:-${TMPDIR:-/tmp}/${hostname}-run}"
memory_mb="${HOME_SERVER_VM_MEMORY_MB:-8192}"
cpu_cores="${HOME_SERVER_VM_CPU_CORES:-4}"
snapshot_mode="${HOME_SERVER_VM_SNAPSHOT:-1}"
net_mode="${HOME_SERVER_VM_NET_MODE:-nat}"
guest_ip_timeout="${HOME_SERVER_VM_GUEST_IP_TIMEOUT:-90}"
rebuild_raw="${HOME_SERVER_VM_REBUILD_RAW:-0}"
keep_work_disk="${HOME_SERVER_VM_KEEP_WORK_DISK:-0}"
vmnet_use_sudo="${HOME_SERVER_VM_VMNET_USE_SUDO:-auto}"
vmnet_provider="${HOME_SERVER_VM_VMNET_PROVIDER:-auto}"
vmnet_bin="${HOME_SERVER_VM_VMNET_BIN:-}"
vmnet_helper_bin="${HOME_SERVER_VM_VMNET_HELPER_BIN:-}"
vmnet_interface_id="${HOME_SERVER_VM_VMNET_INTERFACE_ID:-$(uuidgen 2> /dev/null || true)}"
rebuild_store_image="${HOME_SERVER_VM_REBUILD_STORE_IMAGE:-0}"
default_age_identity="${HOME}/.ssh/id_ed25519"
age_identity_file="${HOME_SERVER_VM_AGE_IDENTITY_FILE:-${default_age_identity}}"

if [[ -z ${vmnet_interface_id} ]]; then
  vmnet_interface_id="$(
    python3 - << 'PY'
import uuid
print(uuid.uuid4())
PY
  )"
fi

if [[ -z ${HOME_SERVER_VM_NET_MAC:-} ]]; then
  hash="$(printf '%s' "${hostname}" | shasum | awk '{print $1}')"
  net_mac="02:${hash:0:2}:${hash:2:2}:${hash:4:2}:${hash:6:2}:${hash:8:2}"
else
  net_mac="$(printf '%s' "${HOME_SERVER_VM_NET_MAC}" | tr '[:upper:]' '[:lower:]')"
fi

nix build "${flake_ref}#nixosConfigurations.${hostname}.config.system.build.vm" --no-link > /dev/null
build_output="$(nix path-info "${flake_ref}#nixosConfigurations.${hostname}.config.system.build.vm")"
qemu_output="$(nix build nixpkgs#qemu --no-link --print-out-paths | tail -n 1)"
e2fs_output="$(nix build nixpkgs#e2fsprogs --no-link --print-out-paths | grep -- '-bin$' | tail -n 1)"
vfkit_output="$(nix build nixpkgs#vfkit --no-link --print-out-paths | tail -n 1)"
tar_output="$(nix build nixpkgs#gnutar --no-link --print-out-paths | tail -n 1)"
erofs_output="$(nix build nixpkgs#erofs-utils --no-link --print-out-paths | tail -n 1)"

qemu_img="${qemu_output}/bin/qemu-img"
mkfs_ext4="${e2fs_output}/bin/mkfs.ext4"
vfkit_bin="${vfkit_output}/bin/vfkit"
tar_bin="${tar_output}/bin/tar"
mkfs_erofs_bin="${erofs_output}/bin/mkfs.erofs"

run_script="${build_output}/bin/run-${hostname}-vm"
kernel_path="$(grep -o '/nix/store/[^ ]*/kernel' "${run_script}" | head -n 1)"
top_system="$(dirname -- "${kernel_path}")"
initrd_path="$(grep -o '/nix/store/[^ ]*/initrd' "${run_script}" | head -n 1)"
reg_info="$(grep -o 'regInfo=/nix/store/[^ ]*' "${run_script}" | head -n 1 | sed 's/^regInfo=//')"
store_paths_file="$(grep -o '/nix/store/[^ ]*-closure-info/store-paths' "${run_script}" | head -n 1)"

if file "${kernel_path}" | grep -qi 'compressed'; then
  printf 'Kernel path appears compressed and is not compatible with vfkit Linux boot on Apple Silicon: %s\n' "${kernel_path}" >&2
  exit 1
fi

if [[ ! -e ${disk_image} ]]; then
  raw_image="$(mktemp "${TMPDIR:-/tmp}/${hostname}.raw.XXXXXX")"
  trap 'rm -f "${raw_image}"' EXIT
  "${qemu_img}" create -f raw "${raw_image}" 131072M > /dev/null
  "${mkfs_ext4}" -L nixos "${raw_image}" > /dev/null 2>&1
  "${qemu_img}" convert -f raw -O qcow2 "${raw_image}" "${disk_image}"
fi

mkdir -p "${run_dir}"
guest_ip_file="${run_dir}/guest-ip"
guest_mac_file="${run_dir}/guest-mac"
runner_mode_file="${run_dir}/runner-mode"
helper_socket="${run_dir}/vmnet-helper.sock"
helper_info_file="${run_dir}/vmnet-helper.json"
vmnet_info_file="${run_dir}/vmnet.json"
vmnet_log_file="${run_dir}/vmnet-provider.log"
serial_log="${run_dir}/vfkit-serial.log"
xchg_dir="${run_dir}/xchg"
work_raw="${run_dir}/${hostname}.work.raw"
base_raw="${flake_dir}/${hostname}.raw"
store_img="${run_dir}/${hostname}.store.img"
secrets_img="${run_dir}/${hostname}.secrets.img"
store_ref_file="${run_dir}/${hostname}.store.vfkit.ref"

mkdir -p "${xchg_dir}"

rm -f "${guest_ip_file}" "${guest_mac_file}" "${runner_mode_file}" "${helper_info_file}" "${vmnet_info_file}" "${helper_socket}"

if [[ ${rebuild_raw} == "1" || ! -e ${base_raw} || ${disk_image} -nt ${base_raw} ]]; then
  printf 'Preparing base raw disk for vfkit: %s\n' "${base_raw}"
  "${qemu_img}" convert -f qcow2 -O raw "${disk_image}" "${base_raw}"
fi

if [[ ${snapshot_mode} == "1" ]]; then
  rm -f "${work_raw}"
  if cp -c "${base_raw}" "${work_raw}" 2> /dev/null; then
    :
  else
    cp "${base_raw}" "${work_raw}"
  fi
  run_disk="${work_raw}"
else
  run_disk="${base_raw}"
fi

stored_store_ref=""
if [[ -f ${store_ref_file} ]]; then
  stored_store_ref="$(head -n 1 "${store_ref_file}" | tr -d '[:space:]')"
fi

if [[ ${rebuild_raw} == "1" || ${rebuild_store_image} == "1" || ! -e ${store_img} || ${stored_store_ref} != "${store_paths_file}" ]]; then
  "${tar_bin}" --create \
    --absolute-names \
    --verbatim-files-from \
    --transform 'flags=rSh;s|/nix/store/||' \
    --transform 'flags=rSh;s|~nix~case~hack~[[:digit:]]\+||g' \
    --files-from "${store_paths_file}" \
                                       | "${mkfs_erofs_bin}" \
      --quiet \
      --force-uid=0 \
      --force-gid=0 \
      -L nix-store \
      -T 0 \
      --hard-dereference \
      --tar=f \
      "${store_img}"
  printf '%s\n' "${store_paths_file}" > "${store_ref_file}"
fi

if [[ -f ${age_identity_file} ]]; then
  secrets_root="$(mktemp -d "${run_dir}/vm-secrets.XXXXXX")"
  install -m 0600 "${age_identity_file}" "${secrets_root}/id_ed25519"
  "${mkfs_erofs_bin}" --quiet -L vm-secrets "${secrets_img}" "${secrets_root}"
  chmod 600 "${secrets_img}"
  rm -rf "${secrets_root}"
else
  rm -f "${secrets_img}"
fi

helper_pid=""
ip_probe_pid=""
ip_hint_prefix=""
vmnet_provider_selected=""
vmnet_provider_detail=""

cleanup() {
  if [[ -n ${helper_pid} ]] && ps -p "${helper_pid}" > /dev/null 2>&1; then
    kill "${helper_pid}" > /dev/null 2>&1 || true
    wait "${helper_pid}" > /dev/null 2>&1 || true
    helper_pid=""
  fi
  if [[ -n ${ip_probe_pid} ]] && ps -p "${ip_probe_pid}" > /dev/null 2>&1; then
    kill "${ip_probe_pid}" > /dev/null 2>&1 || true
    wait "${ip_probe_pid}" > /dev/null 2>&1 || true
  fi
  if [[ ${keep_work_disk} != "1" && ${snapshot_mode} == "1" ]]; then
    rm -f "${work_raw}"
  fi
  rm -f "${secrets_img}"
}
trap cleanup EXIT INT TERM

resolve_guest_ip_from_leases() {
  local target_mac="$1"
  local target_name="$2"
  local ip_prefix="$3"
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

wait_for_guest_ip() {
  local deadline=$((SECONDS + guest_ip_timeout))
  while ((SECONDS < deadline)); do
    if guest_ip="$(resolve_guest_ip_from_leases "${net_mac}" "${hostname}" "${ip_hint_prefix}" 2> /dev/null || true)" && [[ -n ${guest_ip} ]]; then
      printf '%s\n' "${guest_ip}" > "${guest_ip_file}"
      return 0
    fi
    sleep 1
  done
  return 1
}

find_vmnet_helper_bin() {
  local helper_pkg_output helper_pkg_candidate helper_from_path

  if [[ -n ${vmnet_bin} ]]; then
    printf '%s\n' "${vmnet_bin}"
    return 0
  fi

  if [[ -n ${vmnet_helper_bin} ]]; then
    printf '%s\n' "${vmnet_helper_bin}"
    return 0
  fi

  if helper_from_path="$(command -v vmnet-helper 2> /dev/null || true)" && [[ -n ${helper_from_path} ]]; then
    printf '%s\n' "${helper_from_path}"
    return 0
  fi

  helper_pkg_output="$(nix build "${flake_ref}#vmnet-helper" --no-link --print-out-paths 2> /dev/null | tail -n 1)"
  helper_pkg_candidate="${helper_pkg_output}/bin/vmnet-helper"
  if [[ -x ${helper_pkg_candidate} ]]; then
    printf '%s\n' "${helper_pkg_candidate}"
    return 0
  fi

  for candidate in \
    "/opt/homebrew/opt/vmnet-helper/libexec/vmnet-helper" \
    "/opt/vmnet-helper/bin/vmnet-helper" \
    "/usr/local/opt/vmnet-helper/libexec/vmnet-helper"; do
    if [[ -x ${candidate} ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

macos_major_version() {
  local version
  version="$(sw_vers -productVersion 2> /dev/null || true)"
  if [[ -z ${version} ]]; then
    printf '0\n'
    return
  fi
  printf '%s\n' "${version%%.*}"
}

extract_vmnet_prefix_hint() {
  python3 - "$1" << 'PY'
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
        sys.exit(0)
PY
}

write_vmnet_metadata() {
  python3 - "${helper_info_file}" "${vmnet_info_file}" "${vmnet_provider_selected}" "${net_mode}" "${helper_socket}" "${vmnet_provider_detail}" << 'PY'
import json
import sys

src, dst, provider, mode, socket_path, detail = sys.argv[1:]

payload = {
    "provider": provider,
    "mode": mode,
    "socket": socket_path,
    "detail": detail,
}

try:
    with open(src, "r", encoding="utf-8") as fh:
        info = json.load(fh)
    if isinstance(info, dict):
        payload.update(info)
except Exception:
    pass

with open(dst, "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
}

start_vmnet_helper() {
  local helper_bin mode selected errors major
  helper_bin="$(find_vmnet_helper_bin || true)"
  if [[ -z ${helper_bin} ]]; then
    echo "vmnet helper backend is required for ${net_mode} mode but no vmnet-helper binary was found." >&2
    echo "Install the repo package with: nix build ${flake_ref}#vmnet-helper" >&2
    echo "Or enter the dev shell so vmnet-helper is on PATH." >&2
    exit 1
  fi

  case "${net_mode}" in
    vmnet-shared)
      mode="shared"
      ;;
    vmnet-host)
      mode="host"
      ;;
    *)
      echo "Unsupported HOME_SERVER_VM_NET_MODE for vmnet-helper: ${net_mode}" >&2
      exit 1
      ;;
  esac

  local -a helper_cmd
  local -a attempts
  major="$(macos_major_version)"
  case "${vmnet_provider}" in
    auto)
      if ((major >= 26)); then
        attempts=(broker helper)
      else
        attempts=(helper broker)
      fi
      ;;
    broker | helper)
      attempts=("${vmnet_provider}")
      ;;
    *)
      echo "Unsupported HOME_SERVER_VM_VMNET_PROVIDER value: ${vmnet_provider}" >&2
      exit 1
      ;;
  esac

  start_helper_attempt() {
    local with_sudo="$1"
    local -a cmd
    cmd=("${helper_cmd[@]}")
    if [[ ${with_sudo} == "1" ]]; then
      cmd=(sudo --non-interactive "${cmd[@]}")
    fi

    rm -f "${helper_info_file}" "${helper_socket}" "${helper_socket}.lock" "${vmnet_info_file}"
    "${cmd[@]}" > "${helper_info_file}" 2>> "${vmnet_log_file}" &
    helper_pid="$!"

    for _ in $(seq 1 12); do
      if [[ -s ${helper_info_file} ]]; then
        return 0
      fi
      sleep 1
    done

    if [[ -n ${helper_pid} ]] && ps -p "${helper_pid}" > /dev/null 2>&1; then
      kill "${helper_pid}" > /dev/null 2>&1 || true
    fi
    return 1
  }

  try_provider() {
    local provider="$1"
    if [[ ${provider} == "broker" ]]; then
      helper_cmd=("${helper_bin}" --socket "${helper_socket}" --network "${mode}")
      vmnet_provider_detail="vmnet-helper --network ${mode}"
    else
      helper_cmd=("${helper_bin}" --socket "${helper_socket}" --operation-mode "${mode}" --interface-id "${vmnet_interface_id}")
      vmnet_provider_detail="vmnet-helper --operation-mode ${mode}"
    fi

    if [[ ${vmnet_use_sudo} == "1" ]]; then
      start_helper_attempt "1"
      return $?
    fi

    if [[ ${vmnet_use_sudo} == "0" ]]; then
      start_helper_attempt "0"
      return $?
    fi

    if start_helper_attempt "0"; then
      return 0
    fi

    if start_helper_attempt "1"; then
      vmnet_use_sudo="1"
      return 0
    fi

    return 1
  }

  errors=()
  selected=""
  rm -f "${vmnet_log_file}"
  for provider in "${attempts[@]}"; do
    if try_provider "${provider}"; then
      selected="${provider}"
      break
    fi
    echo "WARN: vmnet provider ${provider} failed, trying next provider" >&2
    errors+=("${provider}")
  done

  if [[ -z ${selected} ]]; then
    echo "vmnet helper backend failed to start for ${net_mode} (attempted: ${errors[*]}). See ${vmnet_log_file}" >&2
    exit 1
  fi

  vmnet_provider_selected="${selected}"
  write_vmnet_metadata
  ip_hint_prefix="$(extract_vmnet_prefix_hint "${vmnet_info_file}" || true)"

  echo "Using vmnet provider: ${vmnet_provider_selected} (${vmnet_provider_detail})" >&2
}

kernel_params="$(cat "${top_system}/kernel-params") init=${top_system}/init regInfo=${reg_info} console=hvc0"
bootloader_arg="linux,kernel=${kernel_path},initrd=${initrd_path},cmdline=\"${kernel_params}\""

network_device_arg=""
case "${net_mode}" in
  nat)
    network_device_arg="virtio-net,nat,mac=${net_mac}"
    vmnet_provider_selected="nat"
    ;;
  vmnet-shared | vmnet-host)
    start_vmnet_helper
    network_device_arg="virtio-net,unixSocketPath=${helper_socket},mac=${net_mac}"
    ;;
  *)
    echo "Unsupported HOME_SERVER_VM_NET_MODE value: ${net_mode}" >&2
    exit 1
    ;;
esac

printf 'Starting %s (vfkit)\n' "${hostname}"
printf '  memory_mb: %s\n' "${memory_mb}"
printf '  cpu_cores: %s\n' "${cpu_cores}"
printf '  snapshot: %s\n' "${snapshot_mode}"
printf '  net_mode: %s\n' "${net_mode}"
if [[ ${net_mode} == vmnet-shared || ${net_mode} == vmnet-host ]]; then
  printf '  vmnet_provider: %s\n' "${vmnet_provider_selected}"
fi
printf '  net_mac: %s\n' "${net_mac}"
printf '  run_disk: %s\n' "${run_disk}"
if [[ -f ${secrets_img} ]]; then
  printf '  vm_secrets: %s\n' "${age_identity_file}"
fi

printf '%s\n' "${net_mac}" > "${guest_mac_file}"
printf '%s\n' "vfkit-${net_mode}-${vmnet_provider_selected}" > "${runner_mode_file}"

extra_device_args=()
if [[ -f ${secrets_img} ]]; then
  extra_device_args+=(--device "virtio-blk,path=${secrets_img}")
fi

( 
  if wait_for_guest_ip; then
    echo "Resolved guest IP: $(cat "${guest_ip_file}")" >&2
  else
    echo "WARN: did not resolve guest IP from /var/db/dhcpd_leases within ${guest_ip_timeout}s" >&2
  fi
) &
ip_probe_pid="$!"

"${vfkit_bin}" \
  --cpus "${cpu_cores}" \
  --memory "${memory_mb}" \
  --bootloader "${bootloader_arg}" \
  --device "virtio-blk,path=${run_disk}" \
  --device "virtio-blk,path=${store_img}" \
  "${extra_device_args[@]}" \
  --device "${network_device_arg}" \
  --device virtio-rng \
  --device "virtio-serial,logFilePath=${serial_log}"
