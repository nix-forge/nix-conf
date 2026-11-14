# shellcheck shell=bash
# Bound Go's normal heap growth; systemd supplies the hard RAM/swap boundary.
export GOGC="${GOGC:-100}"
export GOMEMLIMIT="${GOMEMLIMIT:-6GiB}"
# Non-interactive Restic otherwise suppresses all progress until completion.
# Emit one status per minute; operators can override this for diagnostics.
export RESTIC_PROGRESS_FPS="${RESTIC_PROGRESS_FPS:-0.016666}"
# Keep the shared lock across Restic and its descendants. Repository lock waits
# still protect against maintenance started outside this workstation lane.
exec @flock@ --exclusive --no-fork @bulkLock@ @restic@ --retry-lock 30m "$@"
