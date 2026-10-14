#!/usr/bin/env bash
#
# Run the Digital Man voice proxy (Node.js) directly on the host.
#
# The script is self-supervising:
#   * It starts a supervisor loop that launches the Node.js worker with
#     `nohup ... &`.
#   * If the worker (run-node.sh / node) is killed, the supervisor waits
#     `RESTART_DELAY` seconds and re-runs it with `nohup ... &` again.
#
# Usage:
#   ./run-node.sh              # daemonize supervisor via nohup, then exit
#   ./run-node.sh --foreground # keep supervisor in the foreground (systemd/debug)
#   ./run-node.sh --stop       # stop supervisor and worker
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export MONGODB_URI="${MONGODB_URI:-mongodb://192.168.168.33:27017,192.168.168.33:27018,192.168.168.33:27019/?replicaSet=rs0}"
export MONGODB_DB="${MONGODB_DB:-voice_helper_db}"
export DIGITALMAN_DB="${DIGITALMAN_DB:-digitalman_db}"
export REDIS_URL="${REDIS_URL:-redis://192.168.168.33:6379}"
export VOICE_SCHEME="${VOICE_SCHEME:-http}"
export VOICE_HOST="${VOICE_HOST:-192.168.168.33}"
export VOICE_PORT="${VOICE_PORT:-33002}"
export VOICE_TTS_PATH="${VOICE_TTS_PATH:-/tts}"
export TRUST_PROXY="${TRUST_PROXY:-true}"
export DIGITALMAN_PROXY_HOST="${DIGITALMAN_PROXY_HOST:-0.0.0.0}"
export DIGITALMAN_PROXY_PORT="${DIGITALMAN_PROXY_PORT:-8083}"
export DIGITALMAN_TIMEOUT="${DIGITALMAN_TIMEOUT:-600}"

LOG_FILE="${LOG_FILE:-$HERE/nohup.out}"
SUPERVISOR_PID_FILE="${SUPERVISOR_PID_FILE:-$HERE/.run-node.supervisor.pid}"
WORKER_PID_FILE="${WORKER_PID_FILE:-$HERE/.run-node.worker.pid}"
RESTART_DELAY="${RESTART_DELAY:-3}"
NODE_BIN="${NODE_BIN:-node}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# ---------------------------------------------------------------------------
# Worker role: become the actual Node.js process.
# ---------------------------------------------------------------------------
run_worker() {
    log "Starting Digital Man voice proxy (Node.js)"
    log "  Listen:   ${DIGITALMAN_PROXY_HOST}:${DIGITALMAN_PROXY_PORT}"
    log "  MongoDB:  $MONGODB_URI"
    log "  Redis:    $REDIS_URL"
    log "  Voice:    ${VOICE_SCHEME}://${VOICE_HOST}:{TtsBaseUrl|${VOICE_PORT}}"
    exec "$NODE_BIN" "$HERE/server.js"
}

# ---------------------------------------------------------------------------
# Supervisor role: keep the worker alive, (re)launching it with nohup &.
# ---------------------------------------------------------------------------
WORKER_PID=""

stop_worker() {
    if [[ -n "$WORKER_PID" ]] && kill -0 "$WORKER_PID" 2>/dev/null; then
        kill "$WORKER_PID" 2>/dev/null || true
        wait "$WORKER_PID" 2>/dev/null || true
    fi
}

cleanup() {
    log "Supervisor received signal, stopping worker (pid=${WORKER_PID:-none})"
    stop_worker
    rm -f "$SUPERVISOR_PID_FILE" "$WORKER_PID_FILE"
    exit 0
}

run_supervisor() {
    echo "$$" >"$SUPERVISOR_PID_FILE"
    trap cleanup SIGINT SIGTERM

        nohup env RUN_NODE_WORKER=1 "${BASH_SOURCE[0]}" >>"$LOG_FILE" 2>&1 &
        WORKER_PID=$!
        echo "$WORKER_PID" >"$WORKER_PID_FILE"
        log "Worker started (pid=$WORKER_PID), logging to $LOG_FILE"

        wait "$WORKER_PID" 2>/dev/null
        log "Worker (pid=$WORKER_PID) exited, restarting in ${RESTART_DELAY}s..."
        sleep "$RESTART_DELAY"
}

# ---------------------------------------------------------------------------
# Entry point.
# ---------------------------------------------------------------------------
stop_all() {
    local spid="" wpid="" stopped=0
    if [[ -f "$SUPERVISOR_PID_FILE" ]]; then
        spid="$(cat "$SUPERVISOR_PID_FILE" 2>/dev/null || true)"
        if [[ -n "$spid" ]] && kill -0 "$spid" 2>/dev/null; then
            log "Stopping supervisor (pid=$spid)"
            kill "$spid" 2>/dev/null || true
            stopped=1
        fi
    fi
    if [[ -f "$WORKER_PID_FILE" ]]; then
        wpid="$(cat "$WORKER_PID_FILE" 2>/dev/null || true)"
        if [[ -n "$wpid" ]] && kill -0 "$wpid" 2>/dev/null; then
            log "Stopping worker (pid=$wpid)"
            kill "$wpid" 2>/dev/null || true
            stopped=1
        fi
    fi

    # Give processes up to ~3s to exit gracefully, then force kill.
    local i
    for i in $(seq 1 10); do
        if { [[ -n "$spid" ]] && kill -0 "$spid" 2>/dev/null; } || \
           { [[ -n "$wpid" ]] && kill -0 "$wpid" 2>/dev/null; }; then
            sleep 0.3
        else
            break
        fi
    done
    if [[ -n "$spid" ]] && kill -0 "$spid" 2>/dev/null; then
        log "Supervisor (pid=$spid) did not exit, sending SIGKILL"
        kill -9 "$spid" 2>/dev/null || true
    fi
    if [[ -n "$wpid" ]] && kill -0 "$wpid" 2>/dev/null; then
        log "Worker (pid=$wpid) did not exit, sending SIGKILL"
        kill -9 "$wpid" 2>/dev/null || true
    fi
    rm -f "$SUPERVISOR_PID_FILE" "$WORKER_PID_FILE"
    if [[ "$stopped" == "1" ]]; then
        log "Previous instance stopped."
    fi
}

if [[ "${RUN_NODE_WORKER:-}" == "1" ]]; then
    run_worker
fi

if [[ "${RUN_NODE_SUPERVISOR:-}" == "1" ]]; then
    run_supervisor
fi

case "${1:-}" in
    --stop)
        stop_all
        exit 0
        ;;
    --foreground)
        run_supervisor
        ;;
    --help|-h)
        sed -n '2,14p' "${BASH_SOURCE[0]}"
        exit 0
        ;;
    *)
        stop_all
        sleep 1
        nohup env RUN_NODE_SUPERVISOR=1 "${BASH_SOURCE[0]}" >>"$LOG_FILE" 2>&1 &
        SUPERVISOR_PID=$!
        echo "$SUPERVISOR_PID" >"$SUPERVISOR_PID_FILE"
        log "Supervisor started (pid=$SUPERVISOR_PID); it will keep node alive."
        log "Logs:   $LOG_FILE"
        log "Stop:   $0 --stop"
        ;;
esac
