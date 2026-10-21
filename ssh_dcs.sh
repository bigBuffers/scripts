#!/usr/bin/env bash
set -euo pipefail

# Prefer SSH keys; optionally supply a password through DCS_SSH_PASSWORD.
target="${DCS_SSH_USER:-${USER}}@${DCS_SSH_HOST:-dcs-sh01.nvidia.com}"
if [[ -n "${DCS_SSH_PASSWORD:-}" ]]; then
    command -v sshpass >/dev/null 2>&1 || {
        printf 'sshpass is required when DCS_SSH_PASSWORD is set.\n' >&2
        exit 1
    }
    export SSHPASS="$DCS_SSH_PASSWORD"
    unset DCS_SSH_PASSWORD
    exec sshpass -e ssh "$target" "$@"
fi
exec ssh "$target" "$@"
