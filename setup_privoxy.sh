#!/usr/bin/env bash
#
# setup_privoxy.sh - Set up Privoxy on your local machine to forward traffic
# through a SOCKS5 proxy established via an SSH dynamic tunnel.
#
# Usage:
#   ./setup_privoxy.sh                # run full setup (install + config + restart)
#   ./setup_privoxy.sh tunnel         # (re)establish the SSH dynamic tunnel
#   ./setup_privoxy.sh check          # verify the proxy is working
#   ./setup_privoxy.sh env            # print the env vars to export
#
set -euo pipefail

# ---- Configuration (edit to match your environment) -------------------------
PRIVOXY_LISTEN="127.0.0.1:8118"   # Local interface Privoxy listens on (default port 8118)
SOCKS_HOST="127.0.0.1"            # SOCKS5 proxy host (the SSH tunnel endpoint)
SOCKS_PORT="1080"                 # SOCKS5 proxy port (must match the ssh -D port below)
PRIVOXY_CONFIG="/etc/privoxy/config"

SSH_USER="sqin"
SSH_HOST="dc2-container-xterm-019.prd.it.nvidia.com"
SSH_PORT="2121"
# -----------------------------------------------------------------------------

log() { printf '\033[1;32m[privoxy-setup]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[privoxy-setup]\033[0m %s\n' "$*" >&2; }

install_privoxy() {
    if command -v privoxy >/dev/null 2>&1; then
        log "Privoxy already installed: $(command -v privoxy)"
        return
    fi
    log "Installing Privoxy (Linux/Ubuntu) ..."
    sudo apt update && sudo apt install -y privoxy
}

configure_privoxy() {
    local listen_line="listen-address ${PRIVOXY_LISTEN}"
    local forward_line="forward-socks5 / ${SOCKS_HOST}:${SOCKS_PORT} ."

    log "Configuring ${PRIVOXY_CONFIG} ..."

    if ! sudo grep -qF "${listen_line}" "${PRIVOXY_CONFIG}" 2>/dev/null; then
        echo "${listen_line}  # Listen on local interface only, 8118 is the default port of Privoxy" \
            | sudo tee -a "${PRIVOXY_CONFIG}" >/dev/null
        log "Appended: ${listen_line}"
    else
        log "listen-address already present, skipping"
    fi

    if ! sudo grep -qF "${forward_line}" "${PRIVOXY_CONFIG}" 2>/dev/null; then
        echo "${forward_line}  # Forward all traffic to SOCKS5 proxy (SSH tunnel)" \
            | sudo tee -a "${PRIVOXY_CONFIG}" >/dev/null
        log "Appended: ${forward_line}"
    else
        log "forward-socks5 already present, skipping"
    fi
}

restart_privoxy() {
    log "Restarting Privoxy ..."
    sudo service privoxy restart
}

establish_tunnel() {
    if pgrep -f "ssh -D ${SOCKS_PORT}" >/dev/null 2>&1; then
        log "SSH dynamic tunnel on port ${SOCKS_PORT} already running."
        return
    fi
    log "Establishing SSH dynamic tunnel: -D ${SOCKS_PORT} -p ${SSH_PORT} ${SSH_USER}@${SSH_HOST}"
    log "NOTE: KEEP this tunnel alive! (-f -N runs it in the background)"
    ssh -D "${SOCKS_PORT}" -p "${SSH_PORT}" -f -N "${SSH_USER}@${SSH_HOST}"
}

check_proxy() {
    log "Checking proxy via http://${PRIVOXY_LISTEN} ..."
    log "Local egress IP (through proxy):"
    curl -x "http://${PRIVOXY_LISTEN}" https://ifconfig.me || err "Proxy check failed"
    echo
}

print_env() {
    cat <<EOF
# Export these before launching Claude Code (add to ~/.bashrc or ~/.zshrc):
export HTTPS_PROXY=http://${PRIVOXY_LISTEN}
export HTTP_PROXY=http://${PRIVOXY_LISTEN}

# Optional: auto-start Privoxy if not running (add to ~/.bashrc or ~/.zshrc):
# if ! pgrep -x privoxy >/dev/null; then privoxy ${PRIVOXY_CONFIG} & fi
EOF
}

main() {
    case "${1:-setup}" in
        setup)
            install_privoxy
            configure_privoxy
            restart_privoxy
            establish_tunnel
            check_proxy
            print_env
            log "Done. Remember to KEEP the SSH tunnel terminal alive!"
            ;;
        tunnel)  establish_tunnel ;;
        check)   check_proxy ;;
        env)     print_env ;;
        *)
            err "Unknown command: $1"
            echo "Usage: $0 [setup|tunnel|check|env]" >&2
            exit 1
            ;;
    esac
}

main "$@"
