#!/usr/bin/env bash
# Connect to the lab PC. Prefer SSH keys; optionally supply a password through
# PC_SSH_PASSWORD (environment or .env). Extra arguments are passed to ssh.
set -euo pipefail

# Find the checkout (this file may be a symlink in ~/.local/bin) and load lib + .env.
self="${BASH_SOURCE[0]}"
while [[ -L "$self" ]]; do
    link="$(readlink "$self")"
    case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
. "$(cd "$(dirname "$self")" && pwd)/lib/common.sh"

target="${PC_SSH_USER:-$(default_user)}@${PC_SSH_HOST:-10.19.183.180}"
ssh_with_password "${PC_SSH_PASSWORD:-}" "$target" "$@"
