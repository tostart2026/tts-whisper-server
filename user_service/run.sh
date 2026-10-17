#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export MONGODB_URI="${MONGODB_URI:-mongodb://192.168.168.33:27017,192.168.168.33:27018,192.168.168.33:27019/?replicaSet=rs0}"
export USER_DB="${USER_DB:-base_db}"
export DIGITALMAN_DB="${DIGITALMAN_DB:-digitalman_db}"
export USER_SERVICE_HOST="${USER_SERVICE_HOST:-127.0.0.1}"
export USER_SERVICE_PORT="${USER_SERVICE_PORT:-8080}"

LOG_FILE="${LOG_FILE:-$HERE/nohup.out}"
SUPERVISOR_PID_FILE="${SUPERVISOR_PID_FILE:-$HERE/.run.supervisor.pid}"
WORKER_PID_FILE="${WORKER_PID_FILE:-$HERE/.run.worker.pid}"
RESTART_DELAY="${RESTART_DELAY:-3}"
NODE_BIN="${NODE_BIN:-node}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

run_worker() {
    log "Starting user service (Node.js)"
    log "  Listen:   ${USER_SERVICE_HOST}:${USER_SERVICE_PORT}"
    log "  MongoDB:  $MONGODB_URI"
    log "  User DB:  $USER_DB"
    log "  Voice DB: $DIGITALMAN_DB"
    exec "$NODE_BIN" "$HERE/server.js"
}

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

    while true; do
        nohup env RUN_USER_SERVICE_WORKER=1 "${BASH_SOURCE[0]}" >>"$LOG_FILE" 2>&1 &
        WORKER_PID=$!
        echo "$WORKER_PID" >"$WORKER_PID_FILE"
        log "Worker started (pid=$WORKER_PID), logging to $LOG_FILE"

        wait "$WORKER_PID" 2>/dev/null
        log "Worker (pid=$WORKER_PID) exited, restarting in ${RESTART_DELAY}s..."
        sleep "$RESTART_DELAY"
    done
}

stop_all() {
    local files=("$SUPERVISOR_PID_FILE" "$WORKER_PID_FILE")
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

if [[ "${RUN_USER_SERVICE_WORKER:-}" == "1" ]]; then
    run_worker
fi

if [[ "${RUN_USER_SERVICE_SUPERVISOR:-}" == "1" ]]; then
    run_supervisor
fi

stop_all
sleep 1
nohup env RUN_USER_SERVICE_SUPERVISOR=1 "${BASH_SOURCE[0]}" >>"$LOG_FILE" 2>&1 &
SUPERVISOR_PID=$!
echo "$SUPERVISOR_PID" >"$SUPERVISOR_PID_FILE"
log "Supervisor started (pid=$SUPERVISOR_PID); it will keep node alive."
log "Logs:   $LOG_FILE"
