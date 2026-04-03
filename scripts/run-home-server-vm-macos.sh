#!/usr/bin/env bash
set -euo pipefail

flake_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
flake_ref="path:${flake_dir}"
hostname="${HOME_SERVER_VM_HOSTNAME:-home-server-vm}"
disk_image="${HOME_SERVER_VM_DISK_IMAGE:-${flake_dir}/${hostname}.qcow2}"
run_dir="${HOME_SERVER_VM_RUN_DIR:-${TMPDIR:-/tmp}/${hostname}-run}"
memory_mb="${HOME_SERVER_VM_MEMORY_MB:-8192}"
cpu_cores="${HOME_SERVER_VM_CPU_CORES:-4}"
ssh_port="${HOME_SERVER_VM_SSH_PORT:-}"
ingress_port="${HOME_SERVER_VM_INGRESS_PORT:-${HOME_SERVER_VM_HTTPS_PORT:-${HOME_SERVER_VM_HTTP_PORT:-}}}"
snapshot_mode="${HOME_SERVER_VM_SNAPSHOT:-1}"
disk_cache="${HOME_SERVER_VM_DISK_CACHE:-writeback}"
net_device="${HOME_SERVER_VM_NET_DEVICE:-virtio-net-pci}"
net_backend="${HOME_SERVER_VM_NET_BACKEND:-user}"
accel_mode="${HOME_SERVER_VM_ACCEL:-}"
cpu_model="${HOME_SERVER_VM_CPU_MODEL:-max}"
rebuild_store_image="${HOME_SERVER_VM_REBUILD_STORE_IMAGE:-0}"
default_age_identity="${HOME}/.ssh/id_ed25519"
age_identity_file="${HOME_SERVER_VM_AGE_IDENTITY_FILE:-${default_age_identity}}"
ssh_port_is_default=0
ingress_port_is_default=0
ssh_port_auto_selected=0
ingress_port_auto_selected=0

if [[ -z ${ssh_port} ]]; then
  ssh_port="2222"
  ssh_port_is_default=1
fi

if [[ -z ${ingress_port} ]]; then
  ingress_port="8443"
  ingress_port_is_default=1
fi

port_in_use() {
  local port="$1"
  lsof -nP -iTCP:"${port}" -sTCP:LISTEN > /dev/null 2>&1
}

find_free_port() {
  local start_port="$1"
  local max_tries="${2:-200}"
  local candidate
  local i

  for ((i = 0; i < max_tries; i += 1)); do
    candidate="$((start_port + i))"
    if ! port_in_use "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

nix build "${flake_ref}#nixosConfigurations.${hostname}.config.system.build.vm" --no-link > /dev/null
build_output="$(nix path-info "${flake_ref}#nixosConfigurations.${hostname}.config.system.build.vm")"
qemu_output="$(nix build nixpkgs#qemu --no-link --print-out-paths | tail -n 1)"
e2fs_output="$(nix build nixpkgs#e2fsprogs --no-link --print-out-paths | grep -- '-bin$' | tail -n 1)"
tar_output="$(nix build nixpkgs#gnutar --no-link --print-out-paths | tail -n 1)"
erofs_output="$(nix build nixpkgs#erofs-utils --no-link --print-out-paths | tail -n 1)"
run_script="${build_output}/bin/run-${hostname}-vm"
qemu_system_bin="$(grep -o 'qemu-system-[^ ]*' "${run_script}" | head -n 1)"
kernel_path="$(grep -o '/nix/store/[^ ]*/kernel' "${run_script}" | head -n 1)"
top_system="$(dirname -- "${kernel_path}")"
initrd_path="$(grep -o '/nix/store/[^ ]*/initrd' "${run_script}" | head -n 1)"
reg_info="$(grep -o 'regInfo=/nix/store/[^ ]*' "${run_script}" | head -n 1 | sed 's/^regInfo=//')"
store_paths_file="$(grep -o '/nix/store/[^ ]*-closure-info/store-paths' "${run_script}" | head -n 1)"
qemu_system_path="${qemu_output}/bin/${qemu_system_bin}"
tar_bin="${tar_output}/bin/tar"
mkfs_erofs_bin="${erofs_output}/bin/mkfs.erofs"

if [[ ! -e ${disk_image} ]]; then
  raw_image="$(mktemp "${TMPDIR:-/tmp}/${hostname}.raw.XXXXXX")"
  trap 'rm -f "${raw_image}"' EXIT
  "${qemu_output}/bin/qemu-img" create -f raw "${raw_image}" 131072M > /dev/null
  "${e2fs_output}/bin/mkfs.ext4" -L nixos "${raw_image}" > /dev/null 2>&1
  "${qemu_output}/bin/qemu-img" convert -f raw -O qcow2 "${raw_image}" "${disk_image}"
fi

mkdir -p "${run_dir}/xchg"
store_img="${run_dir}/${hostname}.store.qemu.img"
secrets_img="${run_dir}/${hostname}.secrets.qemu.img"
store_ref_file="${run_dir}/${hostname}.store.qemu.ref"
stored_store_ref=""

cleanup() {
  rm -f "${secrets_img}"
}

trap cleanup EXIT

if [[ -f ${store_ref_file} ]]; then
  stored_store_ref="$(head -n 1 "${store_ref_file}" | tr -d '[:space:]')"
fi

if [[ ${rebuild_store_image} == "1" || ! -e ${store_img} || ${stored_store_ref} != "${store_paths_file}" ]]; then
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

console_device='ttyS0,115200n8'

machine_args=(-machine accel=tcg)
cpu_args=(-cpu "${cpu_model}")
extra_args=()

if [[ ${qemu_system_bin} == 'qemu-system-aarch64' ]]; then
  machine_args=(-machine "virt,gic-version=max,accel=${accel_mode:-hvf:tcg}")
  console_device='ttyAMA0,115200n8'
elif [[ -n ${accel_mode} ]]; then
  machine_args=(-machine "accel=${accel_mode}")
fi

if [[ ${snapshot_mode} != "0" ]]; then
  extra_args+=(-snapshot)
fi

if [[ ${disk_cache} != "none" && ${disk_cache} != "writeback" && ${disk_cache} != "writethrough" && ${disk_cache} != "directsync" && ${disk_cache} != "unsafe" ]]; then
  printf 'Unsupported HOME_SERVER_VM_DISK_CACHE value: %s\n' "${disk_cache}" >&2
  exit 1
fi

netdev_arg=""
forward_summary=""
case "${net_backend}" in
  user)
    if port_in_use "${ssh_port}"; then
      if [[ ${ssh_port_is_default} -eq 1 ]]; then
        next_ssh_port="$(find_free_port 2222 200 || true)"
        if [[ -z ${next_ssh_port} ]]; then
          printf 'Unable to find a free SSH forward port near %s. Set HOME_SERVER_VM_SSH_PORT manually.\n' "${ssh_port}" >&2
          exit 1
        fi

        printf 'WARN: host SSH port %s is in use; using %s instead.\n' "${ssh_port}" "${next_ssh_port}" >&2
        ssh_port="${next_ssh_port}"
        ssh_port_auto_selected=1
      else
        printf 'HOME_SERVER_VM_SSH_PORT=%s is already in use. Pick another port and retry.\n' "${ssh_port}" >&2
        exit 1
      fi
    fi

    if port_in_use "${ingress_port}"; then
      if [[ ${ingress_port_is_default} -eq 1 ]]; then
        next_ingress_port="$(find_free_port 8443 200 || true)"
        if [[ -z ${next_ingress_port} ]]; then
          printf 'Unable to find a free HTTPS forward port near %s. Set HOME_SERVER_VM_INGRESS_PORT manually.\n' "${ingress_port}" >&2
          exit 1
        fi

        printf 'WARN: host HTTPS port %s is in use; using %s instead.\n' "${ingress_port}" "${next_ingress_port}" >&2
        ingress_port="${next_ingress_port}"
        ingress_port_auto_selected=1
      else
        printf 'HOME_SERVER_VM_INGRESS_PORT=%s is already in use. Pick another port and retry.\n' "${ingress_port}" >&2
        exit 1
      fi
    fi

    printf '%s\n' "${ssh_port}" > "${run_dir}/ssh-port"
    printf '%s\n' "${ingress_port}" > "${run_dir}/ingress-port"

    netdev_arg="user,id=user.0,hostfwd=tcp::${ssh_port}-:22,hostfwd=tcp::${ingress_port}-:443"
    forward_summary="tcp ${ssh_port}->22, tcp ${ingress_port}->443"
    ;;
  *)
    printf 'Unsupported HOME_SERVER_VM_NET_BACKEND value: %s\n' "${net_backend}" >&2
    printf 'QEMU runner now supports only HOME_SERVER_VM_NET_BACKEND=user; use vfkit for vmnet networking.\n' >&2
    exit 1
    ;;
esac

kernel_params="$(cat "${top_system}/kernel-params") init=${top_system}/init regInfo=${reg_info} console=${console_device}"

printf 'Starting %s\n' "${hostname}"
printf '  qemu: %s\n' "${qemu_system_bin}"
printf '  machine: %s\n' "${machine_args[*]}"
printf '  cpu: %s\n' "${cpu_args[*]}"
printf '  memory_mb: %s\n' "${memory_mb}"
printf '  cpu_cores: %s\n' "${cpu_cores}"
printf '  snapshot: %s\n' "${snapshot_mode}"
printf '  disk_cache: %s\n' "${disk_cache}"
printf '  net_backend: %s\n' "${net_backend}"
printf '  net_device: %s\n' "${net_device}"
printf '  forwards: %s\n' "${forward_summary}"
if [[ ${ssh_port_auto_selected} -eq 1 || ${ingress_port_auto_selected} -eq 1 ]]; then
  printf '  port_hint: HOME_SERVER_VM_SSH_PORT=%s HOME_SERVER_VM_INGRESS_PORT=%s\n' "${ssh_port}" "${ingress_port}"
fi
printf '  ssh_hint: ssh -p %s testadmin@127.0.0.1\n' "${ssh_port}"
printf '  https_hint: https://127.0.0.1:%s/healthz\n' "${ingress_port}"
printf '  port_files: %s/ssh-port %s/ingress-port\n' "${run_dir}" "${run_dir}"
if [[ -f ${secrets_img} ]]; then
  printf '  vm_secrets: %s\n' "${age_identity_file}"
fi

qemu_args=(
  "${machine_args[@]}"
  "${cpu_args[@]}"
  "-name" "${hostname}"
  "-m" "${memory_mb}"
  "-smp" "${cpu_cores}"
  "-device" "virtio-rng-pci"
  "-device" "${net_device},netdev=user.0"
  "-netdev" "${netdev_arg}"
  "-virtfs" "local,path=/nix/store,security_model=none,mount_tag=nix-store"
  "-virtfs" "local,path=${run_dir}/xchg,security_model=none,mount_tag=shared"
  "-virtfs" "local,path=${run_dir}/xchg,security_model=none,mount_tag=xchg"
  "${extra_args[@]}"
  "-drive" "cache=${disk_cache},file=${disk_image},id=drive1,if=none,index=1,werror=report"
  "-device" "virtio-blk-pci,bootindex=1,drive=drive1,serial=root"
  "-drive" "file=${store_img},id=drive2,if=none,format=raw,readonly=on"
  "-device" "virtio-blk-pci,drive=drive2,serial=nix-store"
  "-kernel" "${kernel_path}"
  "-initrd" "${initrd_path}"
  "-append" "${kernel_params}"
  "-nographic"
)

if [[ -f ${secrets_img} ]]; then
  qemu_args+=(
    "-drive" "file=${secrets_img},id=drive3,if=none,format=raw,readonly=on"
    "-device" "virtio-blk-pci,drive=drive3,serial=vm-secrets"
  )
fi

"${qemu_system_path}" "${qemu_args[@]}"
