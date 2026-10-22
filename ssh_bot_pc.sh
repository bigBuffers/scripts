#!/usr/bin/env bash
# Compatibility wrapper: the Oregon drive-farm bot PC is handled by ssh_drivefarm.sh.
set -euo pipefail

self="${BASH_SOURCE[0]}"
while [[ -L "$self" ]]; do
    link="$(readlink "$self")"
    case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
exec "$(cd "$(dirname "$self")" && pwd)/ssh_drivefarm.sh" oregon "$@"
