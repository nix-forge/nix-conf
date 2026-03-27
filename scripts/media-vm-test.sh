#!/usr/bin/env bash
# shellcheck disable=SC2329

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/media-vm-test-lib.sh
source "$SCRIPT_DIR/media-vm-test-lib.sh"

PROFILE=${1:-smoke}
STAGE=${2:-all}

case "$PROFILE" in
smoke | parity) ;;
*)
	echo "error: profile must be smoke or parity" >&2
	exit 2
	;;
esac

case "$STAGE" in
all | preflight | boot | host-port-bind | forwarding-liveness | guest-services | routes | security | torrent-safety) ;;
*)
	echo "error: unsupported stage '$STAGE'" >&2
	exit 2
	;;
esac

ROOT_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
RUN_ID="$(timestamp_id)-$PROFILE"
ARTIFACT_DIR="$ROOT_DIR/.artifacts/media-vm-tests/$RUN_ID"
DIAG_DIR="$ARTIFACT_DIR/diag"
mkdir -p "$ARTIFACT_DIR" "$DIAG_DIR"

VM_LOG="$ARTIFACT_DIR/vm.log"
PID_FILE="$ARTIFACT_DIR/vm.pid"
GLOBAL_TIMEOUT=${GLOBAL_TIMEOUT:-0}

if [[ $GLOBAL_TIMEOUT -eq 0 ]]; then
	if [[ $PROFILE == "smoke" ]]; then
		GLOBAL_TIMEOUT=480
	else
		GLOBAL_TIMEOUT=1080
	fi
fi

if [[ $PROFILE == "smoke" ]]; then
	BOOT_TIMEOUT=${BOOT_TIMEOUT:-180}
	GUEST_TIMEOUT=${GUEST_TIMEOUT:-120}
else
	BOOT_TIMEOUT=${BOOT_TIMEOUT:-480}
	GUEST_TIMEOUT=${GUEST_TIMEOUT:-240}
fi

PORTS=(2222 8080 8443 8096 5055)
START_TS=$(date +%s)

declare -a STAGE_NAMES=()
declare -a STAGE_STATE=()
declare -a STAGE_SECONDS=()
declare -a STAGE_REASON=()

VM_PID=""
KEEP_VM=${KEEP_VM:-0}
MAIN_STATUS=0

run_with_timeout() {
	local timeout_sec=$1
	shift
	timeout "$timeout_sec" "$@"
}

wait_for_log_marker() {
	local marker=$1
	local timeout_sec=$2
	local deadline=$(($(date +%s) + timeout_sec))
	while (($(date +%s) < deadline)); do
		if grep -Fq "$marker" "$VM_LOG"; then
			return 0
		fi
		if grep -Fq "MEDIA_VM_SELF_TEST_FAIL" "$VM_LOG"; then
			return 1
		fi
		sleep 1
	done
	return 1
}

append_stage() {
	STAGE_NAMES+=("$1")
	STAGE_STATE+=("$2")
	STAGE_SECONDS+=("$3")
	STAGE_REASON+=("$4")
}

stage_log_path() {
	local name=$1
	echo "$ARTIFACT_DIR/stage-$name.log"
}

capture_host_diag() {
	local reason=$1
	{
		echo "reason=$reason"
		echo "captured_at=$(timestamp_utc)"
		echo "profile=$PROFILE"
	} >"$DIAG_DIR/host-context.txt"

	ps -o pid,ppid,etime,command -p "${VM_PID:-0}" >"$DIAG_DIR/ps-vm.txt" 2>&1 || true
	pgrep -fal 'run-media-server-vm-(smoke|parity)-vm|qemu-system-(aarch64|x86_64).*media-server-vm-(smoke|parity)' >"$DIAG_DIR/pgrep.txt" 2>&1 || true
	lsof -nP -iTCP -sTCP:LISTEN >"$DIAG_DIR/lsof-listen.txt" 2>&1 || true
	tail -n 200 "$VM_LOG" >"$DIAG_DIR/vm-log-tail.txt" 2>&1 || true
}

capture_guest_diag() {
	local ssh_opts=(
		-o StrictHostKeyChecking=no
		-o UserKnownHostsFile=/dev/null
		-o ConnectTimeout=2
		-o ConnectionAttempts=1
		-p 2222
	)

	ssh "${ssh_opts[@]}" root@127.0.0.1 "systemctl --failed --no-pager" >"$DIAG_DIR/systemctl-failed.txt" 2>&1 || true
	ssh "${ssh_opts[@]}" root@127.0.0.1 "ss -lntp" >"$DIAG_DIR/ss-lntp.txt" 2>&1 || true
	ssh "${ssh_opts[@]}" root@127.0.0.1 "journalctl -u traefik -u jellyfin -u jellyseerr --no-pager -n 200" >"$DIAG_DIR/journal-services.txt" 2>&1 || true
}

cleanup() {
	if [[ $KEEP_VM -eq 1 ]]; then
		return
	fi
	if [[ -n $VM_PID ]] && kill -0 "$VM_PID" 2>/dev/null; then
		kill "$VM_PID" 2>/dev/null || true
		sleep 1
		kill -9 "$VM_PID" 2>/dev/null || true
	fi
}

trap cleanup EXIT
trap 'echo "interrupted" >&2; MAIN_STATUS=130; exit 130' INT TERM

run_stage() {
	local name=$1
	shift
	local start
	start=$(date +%s)
	local log
	log=$(stage_log_path "$name")

	if "$@" >"$log" 2>&1; then
		append_stage "$name" "PASS" "$(($(date +%s) - start))" "ok"
	else
		local rc=$?
		append_stage "$name" "FAIL" "$(($(date +%s) - start))" "exit $rc"
		capture_host_diag "$name failed"
		capture_guest_diag
		return "$rc"
	fi
}

assert_global_budget() {
	local elapsed=$(($(date +%s) - START_TS))
	if ((elapsed > GLOBAL_TIMEOUT)); then
		echo "global timeout exceeded: ${GLOBAL_TIMEOUT}s"
		return 1
	fi
}

stage_preflight() {
	cd "$ROOT_DIR"
	mkdir -p "$ROOT_DIR/.artifacts/media-vm-tests"
	local p
	for p in "${PORTS[@]}"; do
		if lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
			echo "host port $p is already in use"
			return 1
		fi
	done
	if [[ ! -x "$ROOT_DIR/result/bin/run-media-server-vm-$PROFILE-vm" ]]; then
		just media-vm-build "$PROFILE"
	fi
}

stage_boot() {
	cd "$ROOT_DIR"
	if [[ ! -x "$ROOT_DIR/result/bin/run-media-server-vm-$PROFILE-vm" ]]; then
		just media-vm-build "$PROFILE"
	fi
	nohup "$ROOT_DIR/result/bin/run-media-server-vm-$PROFILE-vm" >"$VM_LOG" 2>&1 &
	VM_PID=$!
	echo "$VM_PID" >"$PID_FILE"

	local deadline=$(($(date +%s) + BOOT_TIMEOUT))
	while (($(date +%s) < deadline)); do
		if ! kill -0 "$VM_PID" 2>/dev/null; then
			echo "vm process exited early"
			return 1
		fi
		if grep -Eq 'Reached target .*Multi-User System|login:|MEDIA_VM_CHECK_TRAEFIK_HTTP_START' "$VM_LOG"; then
			return 0
		fi
		sleep 1
	done
	echo "boot stage timeout after ${BOOT_TIMEOUT}s"
	return 1
}

stage_host_port_bind() {
	local p
	for p in "${PORTS[@]}"; do
		retry_until_success 20 1 run_with_timeout 5 lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null
	done
}

stage_forwarding_liveness() {
	wait_for_log_marker "MEDIA_VM_CHECK_TRAEFIK_HTTP_PASS" 180
}

stage_guest_services() {
	local marker
	for marker in JELLYFIN_ROUTE JELLYSEERR_ROUTE VAULTWARDEN_ROUTE QBITTORRENT_ROUTE NZBGET_ROUTE PIHOLE_ROUTE HOMEBRIDGE_ROUTE SCRYPTED_ROUTE; do
		if grep -Fq "MEDIA_VM_CHECK_${marker}_START" "$VM_LOG"; then
			wait_for_log_marker "MEDIA_VM_CHECK_${marker}_PASS" "$GUEST_TIMEOUT"
		fi
	done
}

stage_routes() {
	wait_for_log_marker "MEDIA_VM_CHECK_RADARR_ROUTE_PASS" "$GUEST_TIMEOUT"
	wait_for_log_marker "MEDIA_VM_CHECK_SONARR_ROUTE_PASS" "$GUEST_TIMEOUT"
	wait_for_log_marker "MEDIA_VM_CHECK_PROWLARR_ROUTE_PASS" "$GUEST_TIMEOUT"
	wait_for_log_marker "MEDIA_VM_CHECK_BAZARR_ROUTE_PASS" "$GUEST_TIMEOUT"
}

stage_security() {
	local marker
	for marker in VAULTWARDEN_PUBLIC_DENY VAULTWARDEN_PUBLIC_ALLOW JELLYFIN_PUBLIC_DENY JELLYFIN_PUBLIC_ALLOW JELLYSEERR_PUBLIC_DENY JELLYSEERR_PUBLIC_ALLOW; do
		if grep -Fq "MEDIA_VM_CHECK_${marker}_START" "$VM_LOG"; then
			wait_for_log_marker "MEDIA_VM_CHECK_${marker}_PASS" "$GUEST_TIMEOUT"
		fi
	done
}

stage_torrent_safety() {
	local marker
	for marker in GLUETUN_HEALTH QBITTORRENT_NETNS_MODE QBITTORRENT_NETNS_SHARED QBITTORRENT_DIRECT_EXPOSED; do
		if grep -Fq "MEDIA_VM_CHECK_${marker}_START" "$VM_LOG"; then
			wait_for_log_marker "MEDIA_VM_CHECK_${marker}_PASS" "$GUEST_TIMEOUT"
		fi
	done
	wait_for_log_marker "MEDIA_VM_SELF_TEST_PASS" "$GUEST_TIMEOUT"
}

run_all() {
	run_stage preflight stage_preflight || return $?
	assert_global_budget || return $?
	run_stage boot stage_boot || return $?
	assert_global_budget || return $?
	run_stage host-port-bind stage_host_port_bind || return $?
	assert_global_budget || return $?
	run_stage forwarding-liveness stage_forwarding_liveness || return $?
	assert_global_budget || return $?
	run_stage guest-services stage_guest_services || return $?
	assert_global_budget || return $?
	run_stage routes stage_routes || return $?
	assert_global_budget || return $?
	run_stage security stage_security || return $?
	assert_global_budget || return $?
	run_stage torrent-safety stage_torrent_safety || return $?
}

if [[ $STAGE == "all" ]]; then
	if run_all; then
		:
	else
		MAIN_STATUS=$?
	fi
else
	case "$STAGE" in
	preflight) run_stage preflight stage_preflight || MAIN_STATUS=$? ;;
	boot) run_stage boot stage_boot || MAIN_STATUS=$? ;;
	host-port-bind) run_stage host-port-bind stage_host_port_bind || MAIN_STATUS=$? ;;
	forwarding-liveness) run_stage forwarding-liveness stage_forwarding_liveness || MAIN_STATUS=$? ;;
	guest-services) run_stage guest-services stage_guest_services || MAIN_STATUS=$? ;;
	routes) run_stage routes stage_routes || MAIN_STATUS=$? ;;
	security) run_stage security stage_security || MAIN_STATUS=$? ;;
	torrent-safety) run_stage torrent-safety stage_torrent_safety || MAIN_STATUS=$? ;;
	esac
fi

TOTAL_SECONDS=$(($(date +%s) - START_TS))
if [[ $MAIN_STATUS -eq 0 ]]; then
	OVERALL="pass"
else
	OVERALL="fail"
fi

write_summary_files "$ARTIFACT_DIR" "$PROFILE" "$TOTAL_SECONDS" "$OVERALL" STAGE_NAMES STAGE_STATE STAGE_SECONDS STAGE_REASON
print_stage_table STAGE_NAMES STAGE_STATE STAGE_SECONDS STAGE_REASON
echo "artifacts: $ARTIFACT_DIR"

exit "$MAIN_STATUS"
