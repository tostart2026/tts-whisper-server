#!/usr/bin/env bash
#
# Run the Digital Man voice proxy (Node.js) directly on the host.
#
# Usage:
#   ./run.sh    # kill any previous instance, then start (takes no arguments)
#
# The script is self-supervising:
#   * It starts a supervisor loop that launches the Node.js worker with
#     `nohup ... &`.
#   * If the worker (node) is killed, the supervisor waits `RESTART_DELAY`
#     seconds and re-runs it with `nohup ... &` again.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export USER_SERVICE_URL="${USER_SERVICE_URL:-http://127.0.0.1:8080}"
export USER_SERVICE_TOKEN="${USER_SERVICE_TOKEN:-}"
export USER_SERVICE_TIMEOUT="${USER_SERVICE_TIMEOUT:-10}"
export REDIS_URL="${REDIS_URL:-redis://192.168.168.33:6379}"
export VOICE_SCHEME="${VOICE_SCHEME:-http}"
export VOICE_HOST="${VOICE_HOST:-192.168.168.33}"
export VOICE_PORT="${VOICE_PORT:-33002}"
export VOICE_TTS_PATH="${VOICE_TTS_PATH:-/tts}"
export TRUST_PROXY="${TRUST_PROXY:-true}"
export DIGITALMAN_PROXY_HOST="${DIGITALMAN_PROXY_HOST:-0.0.0.0}"
export DIGITALMAN_PROXY_PORT="${DIGITALMAN_PROXY_PORT:-8883}"
export DIGITALMAN_TIMEOUT="${DIGITALMAN_TIMEOUT:-600}"

LOG_FILE="${LOG_FILE:-$HERE/nohup.out}"
SUPERVISOR_PID_FILE="${SUPERVISOR_PID_FILE:-$HERE/.run.supervisor.pid}"
WORKER_PID_FILE="${WORKER_PID_FILE:-$HERE/.run.worker.pid}"
LEGACY_SUPERVISOR_PID_FILE="$HERE/.run-node.supervisor.pid"
LEGACY_WORKER_PID_FILE="$HERE/.run-node.worker.pid"
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
    log "  User:     $USER_SERVICE_URL"
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
# Entry point: always stop any previous instance, then start.
# ---------------------------------------------------------------------------
stop_all() {
    local files=("$SUPERVISOR_PID_FILE" "$WORKER_PID_FILE" \
                 "$LEGACY_SUPERVISOR_PID_FILE" "$LEGACY_WORKER_PID_FILE")
    local pids=()
    local f pid i stopped=0

    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        pid="$(cat "$f" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log "Stopping $(basename "$f") (pid=$pid)"
            kill "$pid" 2>/dev/null || true
            pids+=("$pid")
            stopped=1
        else
            rm -f "$f"
        fi
    done

    # Give processes up to ~3s to exit gracefully, then force kill.
    for i in $(seq 1 10); do
        local alive=0
        for pid in "${pids[@]}"; do
            kill -0 "$pid" 2>/dev/null && alive=1
        done
        [[ "$alive" == "1" ]] || break
        sleep 0.3
    done
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log "Process (pid=$pid) did not exit, sending SIGKILL"
            kill -9 "$pid" 2>/dev/null || true
        fi
    done

    rm -f "${files[@]}"
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

stop_all
sleep 1
nohup env RUN_NODE_SUPERVISOR=1 "${BASH_SOURCE[0]}" >>"$LOG_FILE" 2>&1 &
SUPERVISOR_PID=$!
echo "$SUPERVISOR_PID" >"$SUPERVISOR_PID_FILE"
log "Supervisor started (pid=$SUPERVISOR_PID); it will keep node alive."
log "Logs:   $LOG_FILE"
