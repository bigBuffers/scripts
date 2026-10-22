#!/usr/bin/env bash
# Connect to a drive-farm bot PC through the site's jump host and forward the
# VNC port (local 5910 -> remote 5901).
#
# Usage: ssh_drivefarm [oregon|santaclara] [ssh options...]
#        ssh_bot                            (same as: ssh_drivefarm oregon)
#
# Settings (environment or .env): DRIVEFARM_SITE (default oregon),
# DRIVEFARM_USER (default SSH_USER or the local user),
# DRIVEFARM_VNC_LOCAL_PORT, DRIVEFARM_VNC_REMOTE_PORT.
set -euo pipefail

# Find the checkout (this file may be a symlink in ~/.local/bin) and load lib + .env.
self="${BASH_SOURCE[0]}"
while [[ -L "$self" ]]; do
    link="$(readlink "$self")"
    case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
. "$(cd "$(dirname "$self")" && pwd)/lib/common.sh"

usage() {
    cat <<'USAGE'
Usage: ssh_drivefarm [oregon|santaclara] [ssh options...]

Sites:
  oregon      bot PC 255.3.53.95 via sw-ipp-drivefarm-oregon-gp-052.nvidia.com (default)
  santaclara  bot PC 243.48.210.234 via sw-ipp-drivefarm-gp-053.nvidia.com

Forwards local port 5910 to port 5901 on the bot PC for VNC.
USAGE
}

site="${DRIVEFARM_SITE:-oregon}"
case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    ""|-*) ;;                 # no site given: keep the default, pass options to ssh
    *) site="$1"; shift ;;
esac

case "$site" in
    oregon|or)
        jump_host="sw-ipp-drivefarm-oregon-gp-052.nvidia.com"
        bot_host="255.3.53.95"
        ;;
    santaclara|sc)
        jump_host="sw-ipp-drivefarm-gp-053.nvidia.com"
        bot_host="243.48.210.234"
        ;;
    *) usage >&2; die "Unknown site: $site (expected oregon or santaclara)" ;;
esac

user="${DRIVEFARM_USER:-$(default_user)}"
local_port="${DRIVEFARM_VNC_LOCAL_PORT:-5910}"
remote_port="${DRIVEFARM_VNC_REMOTE_PORT:-5901}"

exec ssh -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no \
    -L "${local_port}:localhost:${remote_port}" -qA \
    -o "ProxyCommand ssh -W %h:%p ${user}@${jump_host}" \
    "${user}@${bot_host}" "$@"
