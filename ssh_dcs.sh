#!/usr/bin/env bash
# Connect to the DCS host. Prefer SSH keys; optionally supply a password through
# DCS_SSH_PASSWORD (environment or .env). Extra arguments are passed to ssh.
set -euo pipefail

# Find the checkout (this file may be a symlink in ~/.local/bin) and load lib + .env.
self="${BASH_SOURCE[0]}"
while [[ -L "$self" ]]; do
    link="$(readlink "$self")"
    case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
. "$(cd "$(dirname "$self")" && pwd)/lib/common.sh"

target="${DCS_SSH_USER:-$(default_user)}@${DCS_SSH_HOST:-dcs-sh01.nvidia.com}"
ssh_with_password "${DCS_SSH_PASSWORD:-}" "$target" "$@"
