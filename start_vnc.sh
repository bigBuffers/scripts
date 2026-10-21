#!/usr/bin/env bash
#
# start_vnc.sh - Start an x11vnc server that shares the existing GNOME desktop.
#
# Usage:
#   ./start_vnc.sh           # start the VNC server (default)
#   ./start_vnc.sh start     # start the VNC server
#   ./start_vnc.sh stop      # stop the running VNC server
#   ./start_vnc.sh restart   # restart the VNC server
#   ./start_vnc.sh status    # show whether the server is running + listen ports
#   ./start_vnc.sh log       # tail the x11vnc log
#
set -euo pipefail

# ---- Configuration (edit to match your environment) -------------------------
DISPLAY_NUM=":1"                               # X display of the active GNOME session
RFB_PORT="5900"                                # VNC port (display :0 for viewers)
PASSWD_FILE="${HOME}/.vnc/passwd"              # VNC password file (x11vnc -storepasswd)
LOG_FILE="${HOME}/.vnc/x11vnc.log"             # x11vnc log file
LISTEN_LOCALHOST="false"                        # "true" = bind to localhost only (use SSH tunnel)
# -----------------------------------------------------------------------------

log() { printf '\033[1;32m[start-vnc]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[start-vnc]\033[0m %s\n' "$*" >&2; }

ensure_prereqs() {
    if ! command -v x11vnc >/dev/null 2>&1; then
        err "x11vnc is not installed. Install it with: sudo apt-get install -y x11vnc"
        exit 1
    fi
    if [[ ! -f "${PASSWD_FILE}" ]]; then
        err "VNC password file not found: ${PASSWD_FILE}"
        err "Create it with: x11vnc -storepasswd YOUR_PASSWORD ${PASSWD_FILE}"
        exit 1
    fi
    mkdir -p "$(dirname "${LOG_FILE}")"
}

is_running() {
    pgrep -f "x11vnc .*-rfbport ${RFB_PORT}" >/dev/null 2>&1
}

start_vnc() {
    ensure_prereqs
    if is_running; then
        log "x11vnc already running on port ${RFB_PORT}."
        status_vnc
        return
    fi

    local localhost_flag=""
    if [[ "${LISTEN_LOCALHOST}" == "true" ]]; then
        localhost_flag="-localhost"
        log "Binding to localhost only (connect via SSH tunnel: ssh -L ${RFB_PORT}:localhost:${RFB_PORT} ...)"
    fi

    log "Starting x11vnc on display ${DISPLAY_NUM}, port ${RFB_PORT} ..."
    x11vnc \
        -display "${DISPLAY_NUM}" \
        -auth guess \
        -rfbauth "${PASSWD_FILE}" \
        -rfbport "${RFB_PORT}" \
        -forever \
        -shared \
        ${localhost_flag} \
        -bg \
        -o "${LOG_FILE}"

    sleep 1
    if is_running; then
        log "Started. Connect your VNC viewer to: $(hostname -I 2>/dev/null | awk '{print $1}'):${RFB_PORT}"
        log "Log: ${LOG_FILE}"
    else
        err "x11vnc failed to start. Check the log: ${LOG_FILE}"
        exit 1
    fi
}

stop_vnc() {
    if ! is_running; then
        log "x11vnc is not running."
        return
    fi
    log "Stopping x11vnc ..."
    pkill -f "x11vnc .*-rfbport ${RFB_PORT}" || true
    sleep 1
    if is_running; then
        err "Failed to stop x11vnc."
        exit 1
    fi
    log "Stopped."
}

status_vnc() {
    if is_running; then
        log "x11vnc is RUNNING on port ${RFB_PORT}:"
        pgrep -af "x11vnc .*-rfbport ${RFB_PORT}" || true
    else
        log "x11vnc is NOT running."
    fi
    (ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -E ":${RFB_PORT}\b" || true
}

tail_log() {
    [[ -f "${LOG_FILE}" ]] || { err "No log file at ${LOG_FILE}"; exit 1; }
    tail -n 50 -f "${LOG_FILE}"
}

main() {
    case "${1:-start}" in
        start)   start_vnc ;;
        stop)    stop_vnc ;;
        restart) stop_vnc; start_vnc ;;
        status)  status_vnc ;;
        log)     tail_log ;;
        *)
            err "Unknown command: $1"
            echo "Usage: $0 [start|stop|restart|status|log]" >&2
            exit 1
            ;;
    esac
}

main "$@"
