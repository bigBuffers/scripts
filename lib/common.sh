#!/usr/bin/env bash
# Shared helpers for the scripts in this repository. Source it; do not run it.
#
# Sourcing sets TOOL_DIR to the checkout directory and loads optional local
# settings from "$TOOL_DIR/.env" (see .env.example). Variables that are already
# present in the environment are kept, so one-off overrides still win:
#   DCS_SSH_HOST=other ssh_dcs
#
# Each script finds this file with:
#   self="${BASH_SOURCE[0]}"
#   while [[ -L "$self" ]]; do
#       link="$(readlink "$self")"
#       case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
#   done
#   . "$(cd "$(dirname "$self")" && pwd)/lib/common.sh"

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() {
    printf '%s\n' "$*" >&2
    exit 1
}

# need_cmd NAME [HINT]
need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required.${2:+ $2}"
}

# Username on remote hosts: SSH_USER from .env, else the local user.
default_user() {
    printf '%s' "${SSH_USER:-${USER:-$(id -un)}}"
}

# load_env [FILE]  - KEY=VALUE lines, shell quoting rules; environment wins.
load_env() {
    local file="${1:-$TOOL_DIR/.env}" line key
    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line#export }"
        [[ -z "$line" || "$line" == \#* || "$line" != *=* ]] && continue
        key="${line%%=*}"
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        [[ -n "${!key+x}" ]] && continue
        eval "export $line"
    done < "$file"
}

# ssh_with_password PASSWORD TARGET [ssh args...]
# Uses sshpass when PASSWORD is non-empty, otherwise plain ssh (keys / agent).
ssh_with_password() {
    local password="$1"
    shift
    if [[ -n "$password" ]]; then
        need_cmd sshpass "Install it (macOS: brew install hudochenkov/sshpass/sshpass) or leave the password empty to use SSH keys."
        SSHPASS="$password" exec sshpass -e ssh "$@"
    fi
    exec ssh "$@"
}

load_env
